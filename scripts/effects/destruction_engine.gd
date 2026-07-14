class_name DestructionEngine
extends EffectModule

## Card destruction: protection/replacement checks (can_be_destroyed,
## protects_card_from_destruction, on_would_be_destroyed), zone and strategy
## destruction flows, and the destroy logging.



func destroy_zone_target(player_id: int, target: PlayerState, filter: Callable, prompt: String) -> Dictionary:
	## Let a player choose one of the target player's battle cards matching filter to destroy.
	## filter receives (card_data: Dictionary) -> bool for each zone's top card.
	## Respects can_be_destroyed and on_would_be_destroyed replacement effects.
	## Returns the destroyed card data, or empty dict if nothing was destroyed.
	var valid_zones: Array[int] = []
	for i in range(8):
		var zone_card := target.get_zone_top_card(i)
		if not zone_card.is_empty() and filter.call(zone_card):
			# Check destroy prevention
			if not _can_destroy_card(target, zone_card):
				continue
			valid_zones.append(i)

	if valid_zones.is_empty():
		return {}

	var chosen: int = await h.select_zone_target(player_id, target.player_id, valid_zones, prompt)
	if chosen < 0:
		return {}

	var chosen_card := target.get_zone_top_card(chosen)
	if chosen_card.is_empty():
		return {}

	return await _execute_destroy_zone(target, chosen, chosen_card)




func destroy_zone_targets(player_id: int, target: PlayerState, filter: Callable, count: int, prompt: String, up_to: bool = false) -> Array[Dictionary]:
	## Let a player choose multiple battle cards matching filter to destroy in
	## one batch (revenge deferred per 10.4.3 via destroy_zones).
	## Exact mode (up_to = false): the player must pick count zones, clamped to
	## the number of valid targets. Up-to mode: 0..count, [] declines.
	## Returns the destroyed cards ([] when nothing was destroyed).
	var valid_zones: Array[int] = []
	for i in range(8):
		var zone_card := target.get_zone_top_card(i)
		if not zone_card.is_empty() and filter.call(zone_card):
			if not _can_destroy_card(target, zone_card):
				continue
			valid_zones.append(i)

	if valid_zones.is_empty() or count <= 0:
		return []

	var ask_count: int = count if up_to else mini(count, valid_zones.size())
	if ask_count == 1 or valid_zones.size() == 1:
		# Nothing to multi-select — the single-zone click prompt is better UX
		# than click + confirm (up-to declines via its allow_skip button).
		var zone: int = await h.select_zone_target(player_id, target.player_id, valid_zones, prompt, up_to)
		if zone < 0:
			return []
		return await destroy_zones(target, [zone])

	var chosen: Array[int] = await h.select_zones_target(player_id, target.player_id, valid_zones, ask_count, prompt, up_to)

	# Defensive re-validation (the UI/RPC layer validates too): membership,
	# dedupe, cap at the requested count.
	var cleaned: Array[int] = []
	for zi in chosen:
		if zi in valid_zones and zi not in cleaned:
			cleaned.append(zi)
	if cleaned.size() > ask_count:
		cleaned = cleaned.slice(0, ask_count)
	if cleaned.is_empty():
		return []
	return await destroy_zones(target, cleaned)




func destroy_chosen_zone(player_id: int, target: PlayerState, valid_zones: Array[int], prompt: String) -> Dictionary:
	## Let a player choose one zone from a pre-computed list to destroy.
	## Like destroy_zone_target but with pre-computed valid zones instead of a filter.
	## Respects can_be_destroyed and on_would_be_destroyed replacement effects.
	## Returns the destroyed card data, or empty dict if nothing was destroyed.
	var destroyable: Array[int] = []
	for zi in valid_zones:
		if zi < 0 or zi >= 8 or not target.zone_has_cards(zi):
			continue
		var top_card := target.get_zone_top_card(zi)
		if _can_destroy_card(target, top_card):
			destroyable.append(zi)

	if destroyable.is_empty():
		return {}

	var chosen: int = await h.select_zone_target(player_id, target.player_id, destroyable, prompt)
	if chosen < 0:
		return {}

	var zone_card := target.get_zone_top_card(chosen)
	if zone_card.is_empty():
		return {}

	return await _execute_destroy_zone(target, chosen, zone_card)




func destroy_zones(target: PlayerState, zone_indices: Array[int]) -> Array[Dictionary]:
	## Destroy all occupied zones in the given list on the target player's board.
	## Respects can_be_destroyed and on_would_be_destroyed replacement effects.
	## Returns an array of the destroyed top cards.
	## Revenge triggers are collected as standby entries and resolved after all
	## zones are destroyed, per rules 10.4.3.
	var destroyed: Array[Dictionary] = []
	var deferred: Array = []
	for zi in zone_indices:
		if zi < 0 or zi >= 8 or not target.zone_has_cards(zi):
			continue
		var top_card := target.get_zone_top_card(zi)
		if not _can_destroy_card(target, top_card):
			continue
		var result: Dictionary = await _execute_destroy_zone(target, zi, top_card, deferred)
		if not result.is_empty():
			destroyed.append(result)

	if not destroyed.is_empty():
		target.zones_changed.emit()
		target.discard_changed.emit()
	if not deferred.is_empty():
		await resolve_deferred_entries(deferred)
	return destroyed




func destroy_zone_and_adjacent(player_id: int, target: PlayerState, valid_zones: Array[int], prompt: String, max_rank: int = -1) -> Array[Dictionary]:
	## Let a player choose a zone, then destroy all battle cards in that zone and adjacent zones.
	## If max_rank > 0, only cards with rank <= max_rank are destroyed.
	## valid_zones controls which zones can be chosen (e.g. all 8, or column-restricted).
	## Returns the array of destroyed card data.
	if valid_zones.is_empty():
		return []

	h.pending_destroy_max_rank = max_rank
	var chosen: int = await h.select_zone_target(player_id, target.player_id, valid_zones, prompt)
	h.pending_destroy_max_rank = -1
	if chosen < 0:
		return []

	var affected: Array[int] = [chosen]
	for adj in CardEffect.get_adjacent_zones(chosen):
		if adj not in affected:
			affected.append(adj)

	if max_rank > 0:
		var filtered: Array[int] = []
		for zi in affected:
			var card := target.get_zone_top_card(zi)
			if not card.is_empty() and h.get_effective_field_rank(card, target.player_id) <= max_rank:
				filtered.append(zi)
		return await destroy_zones(target, filtered)
	else:
		return await destroy_zones(target, affected)




func can_destroy_card(target: PlayerState, card_data: Dictionary) -> bool:
	return _can_destroy_card(target, card_data)




func _passes_can_be_destroyed_filter(card_data: Dictionary, watcher_player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["can_be_destroyed"]. When the filter doesn't
	## pass, the card's can_be_destroyed override is skipped (defaulting to
	## "can be destroyed").
	## "caused_by_opponent": bool — true = override fires only when the
	##   opponent's active effect is causing the destruction (e.g.
	##   EBP01-075 "cannot be Destroyed by your opponent's effects").
	## "own_turn": bool — gate by the card owner's turn ownership.
	return TriggerFilters.passes_destruction_gate(
		get_trigger_filter(card_data, "can_be_destroyed"),
		game_state.current_player_id == watcher_player_id, _active_effect_player_id, watcher_player_id)




func _passes_would_be_destroyed_filter(card_data: Dictionary, watcher_player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["on_would_be_destroyed"]. When the filter doesn't
	## pass, the card's replacement hook is skipped (normal destruction proceeds).
	## Same keys as can_be_destroyed: "caused_by_opponent" gates on the opponent's
	## active effect causing the destruction (rule-driven overload/crush have no
	## active effect, so such hooks stay silent there), "own_turn" gates by turn.
	return TriggerFilters.passes_destruction_gate(
		get_trigger_filter(card_data, "on_would_be_destroyed"),
		game_state.current_player_id == watcher_player_id, _active_effect_player_id, watcher_player_id)




func try_destroy_replacement(target: PlayerState, zone_idx: int) -> bool:
	## Apply a <Destroy> replacement effect (on_would_be_destroyed) for the top
	## card of a zone about to be destroyed by a rule action (overload 11.5,
	## crush 11.3). If the hook fires and returns true, the top card moves to
	## the deck bottom instead — it never counts as destroyed — and any cards
	## stacked under it go to the discard (not "destroyed" per 5.12.1.1).
	## Returns true when the destruction was replaced; the zone is left
	## untouched otherwise.
	var top_card := target.get_zone_top_card(zone_idx)
	if top_card.is_empty():
		return false
	var effect := get_effect(top_card)
	if not effect or not _passes_would_be_destroyed_filter(top_card, target.player_id):
		return false
	if not effect.on_would_be_destroyed(_build_context(target.player_id, top_card)):
		return false
	var replaced_stack: Array = target.clear_zone(zone_idx)
	if replaced_stack.size() > 1:
		EffectHandler.banish_or_discard(target, replaced_stack.slice(1))
	target.main_deck.append(top_card)
	target.zones_changed.emit()
	target.deck_changed.emit()
	target.discard_changed.emit()
	return true




func overload_zone(target: PlayerState, zone_idx: int) -> Dictionary:
	## Rule 11.5 overload: destroy a zone's stack to make room for an incoming
	## card. Overload IS <Destroy> (11.5.1), so on_would_be_destroyed replacement
	## effects apply and non-replaced top cards count as destroyed this turn.
	## Revenge never fires — 12.7.2 excludes duplicate-card processing.
	## Returns the overloaded top card ({} if the zone was empty); the caller
	## pushes the incoming card and then fires trigger_leave_play on the result.
	var top_card := target.get_zone_top_card(zone_idx)
	if top_card.is_empty():
		return {}
	if try_destroy_replacement(target, zone_idx):
		return top_card
	var stack: Array = target.clear_zone(zone_idx)
	EffectHandler.banish_or_discard(target, stack)
	target.cards_destroyed_this_turn.append(top_card)
	target.discard_changed.emit()
	return top_card




func _can_destroy_card(target: PlayerState, card_data: Dictionary) -> bool:
	## Check if a card can be destroyed (respects destroy prevention effects).
	## Scans the owner's monster, battle zones, and strategy zones for any
	## active card whose `protects_card_from_destruction` returns true.
	## `card_data` may be a battle card (zone_idx 0-7) or a strategy card
	## (zone_idx -1 since strategies don't sit in numbered zones).
	var effect := get_effect(card_data)
	if effect \
			and _passes_can_be_destroyed_filter(card_data, target.player_id) \
			and not effect.can_be_destroyed(_build_context(target.player_id, card_data)):
		return false

	var card_id: String = card_data.get("id", "")
	var zone_idx: int = -1
	for i in range(8):
		if target.get_zone_top_card(i).get("id", "") == card_id:
			zone_idx = i
			break

	if not target.current_monster.is_empty() \
			and _passes_protects_filter(target.current_monster, target.player_id):
		var m_effect := get_effect(target.current_monster)
		if m_effect and m_effect.protects_card_from_destruction(
				_build_context(target.player_id, target.current_monster), card_data, zone_idx):
			return false
	for i in range(8):
		var zc := target.get_zone_top_card(i)
		if zc.is_empty():
			continue
		if not _passes_protects_filter(zc, target.player_id):
			continue
		var ze := get_effect(zc)
		if ze and ze.protects_card_from_destruction(
				_build_context(target.player_id, zc), card_data, zone_idx):
			return false
	for sz_card in target.strategy_zones:
		if sz_card.is_empty():
			continue
		if not _passes_protects_filter(sz_card, target.player_id):
			continue
		var sz_effect := get_effect(sz_card)
		if sz_effect and sz_effect.protects_card_from_destruction(
				_build_context(target.player_id, sz_card), card_data, zone_idx):
			return false
	return true




func _passes_protects_filter(card_data: Dictionary, watcher_player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["protects_card_from_destruction"] for protector
	## cards. When the filter doesn't pass the override is skipped.
	## Supported keys (same semantics as can_be_destroyed):
	## "caused_by_opponent": bool — true = protect only when opponent's effect
	##   caused the destruction (e.g. EBP04-048 Little Godzilla).
	## "own_turn": bool — gate by the protector's turn ownership.
	return TriggerFilters.passes_destruction_gate(
		get_trigger_filter(card_data, "protects_card_from_destruction"),
		game_state.current_player_id == watcher_player_id, _active_effect_player_id, watcher_player_id)




func _execute_destroy_zone(target: PlayerState, zone_idx: int, top_card: Dictionary, deferred_entries: Variant = null) -> Dictionary:
	## Execute destruction of a single zone, handling replacement effects.
	## When deferred_entries is provided, revenge triggers are collected there
	## instead of resolving immediately (used when destroying multiple zones).
	## Returns the destroyed/replaced card, or empty dict on failure.
	var effect := get_effect(top_card)
	if effect \
			and _passes_would_be_destroyed_filter(top_card, target.player_id) \
			and effect.on_would_be_destroyed(_build_context(target.player_id, top_card)):
		# Replacement: move to deck bottom instead of discard (skip revenge)
		var replaced_stack: Array = target.clear_zone(zone_idx)
		if replaced_stack.size() > 1:
			EffectHandler.banish_or_discard(target, replaced_stack.slice(1))
		target.main_deck.append(top_card)
		target.zones_changed.emit()
		target.deck_changed.emit()
		target.discard_changed.emit()
		_log_destroy(target.player_id, zone_idx, top_card)
		h.card_destroyed.emit(target.player_id, zone_idx)
		return top_card

	var stack: Array = target.clear_zone(zone_idx)
	EffectHandler.banish_or_discard(target, stack)
	target.zones_changed.emit()
	target.discard_changed.emit()
	target.cards_destroyed_this_turn.append(top_card)
	_log_destroy(target.player_id, zone_idx, top_card)
	h.card_destroyed.emit(target.player_id, zone_idx)
	if has_trigger(top_card, "on_destroy"):
		var d_effect := get_effect(top_card)
		@warning_ignore("redundant_await")
		await d_effect.on_destroy(_build_context(target.player_id, top_card), zone_idx)
	# Destroy is one way to leave play — fire the generic hook for linked-card
	# effects that don't care whether removal was via <Destroy> or overload.
	await h.trigger_leave_play(target.player_id, top_card, zone_idx)
	if deferred_entries != null:
		if has_trigger(top_card, "on_revenge"):
			var rev_effect := get_effect(top_card)
			var ctx := _build_context(target.player_id, top_card)
			var revenge_cb := func():
				h.log_message.emit(GameLog.revenge_triggered(target.player_id, top_card.get("id", "")))
				@warning_ignore("redundant_await")
				await rev_effect.on_revenge(ctx)
			deferred_entries.append({"player_id": target.player_id, "card_data": top_card, "callback": revenge_cb, "skip_active_check": true})
		deferred_entries.append_array(h.collect_ally_zone_card_destroyed_entries(target.player_id, top_card, zone_idx))
		deferred_entries.append_array(h.collect_opponent_zone_card_destroyed_entries(target.player_id, top_card, zone_idx))
	else:
		await h.trigger_revenge(target.player_id, top_card)
		await h.trigger_ally_zone_card_destroyed(target.player_id, top_card, zone_idx)
		await h.trigger_opponent_zone_card_destroyed(target.player_id, top_card, zone_idx)
	return top_card




func _log_destroy(target_player_id: int, zone_idx: int, destroyed_card: Dictionary) -> void:
	if not _active_effect_card.is_empty():
		h.log_message.emit(GameLog.effect_destroyed_card(
			_active_effect_player_id, _active_effect_card.get("id", ""),
			target_player_id, zone_idx, destroyed_card.get("id", "")
		))




func get_strategy_discard_interceptor(player_id: int) -> int:
	## Check if any zone card can intercept strategy discards (e.g. EBP02-012 in zone 8).
	## Returns the zone index (0-indexed) of the intercepting card, or -1 if none.
	var player := game_state.players[player_id]
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty():
			var effect := get_effect(zone_card)
			if effect and effect.can_intercept_strategy_discard(_build_context(player_id, zone_card)):
				return i
	return -1




func destroy_strategy_zone(player: PlayerState, zone_index: int) -> Dictionary:
	## Effect-driven destroy of a strategy card. Thin wrapper over
	## discard_strategy_from_zone that takes a PlayerState (ergonomic for card
	## scripts holding ctx.owner / ctx.opponent) and uses default options:
	## interceptor + banish_or_discard + strategy_discarded triggers, with
	## destruction-protection (EBP04-048) honored. Use this instead of raw
	## strategy_zones[i] = {} + discard_pile.append patterns.
	return await discard_strategy_from_zone(player.player_id, zone_index)




func discard_strategy_from_zone(player_id: int, zone_index: int, deferred_entries: Variant = null, bypass_protection: bool = false) -> Dictionary:
	## Remove a strategy card from a strategy zone, applying replacement effects (10.2.1.3).
	## If an interceptor is active, stacks the card under it instead of discarding.
	## When deferred_entries is provided, strategy_discarded triggers are collected there
	## instead of resolving immediately (used during invasion movement).
	## When bypass_protection is true, skips the destruction-protection check —
	## set this for rule-driven moves (start phase discard, invasion-base destruction)
	## that aren't <Destroy> by an effect. Effect-driven destroys leave it false so
	## protectors like EBP04-048 (Little Godzilla) take effect.
	## Returns the removed card (empty dict if zone was already empty or protected).
	var player := game_state.players[player_id]
	var card: Dictionary = player.strategy_zones[zone_index]
	if card.is_empty():
		return {}
	if not bypass_protection and not _can_destroy_card(player, card):
		return {}
	player.strategy_zones[zone_index] = {}
	# Clear any cards stacked under this strategy (e.g. EBP04-089's RAGE markers).
	# RAGE markers never enter the discard pile, so they are dropped, not discarded;
	# the only other under-stack user (EBP03-013) never places real cards there.
	if zone_index < player.strategy_zone_stacks.size():
		player.strategy_zone_stacks[zone_index] = []

	var intercept_zone := get_strategy_discard_interceptor(player_id)
	var intercepted: bool = intercept_zone >= 0
	if intercepted:
		# Let the interceptor card opt out of the replacement (e.g. EBP02-012
		# Frozen Godzilla prompts the player). Default returns true so cards
		# without an override keep mandatory-replacement semantics.
		var interceptor_card: Dictionary = player.get_zone_top_card(intercept_zone)
		var effect := get_effect(interceptor_card)
		if effect:
			@warning_ignore("redundant_await")
			intercepted = await effect.should_intercept_strategy_discard(
				_build_context(player_id, interceptor_card), card)

	if intercepted:
		player.zones[intercept_zone].append(card)
		player.zones_changed.emit()
	else:
		EffectHandler.banish_or_discard(player, [card])
		player.discard_changed.emit()
	player.strategy_zones_changed.emit()

	# Replacement means it wasn't truly discarded — skip discard triggers
	if not intercepted:
		if deferred_entries != null:
			deferred_entries.append_array(h.collect_strategy_discarded_entries(player_id, card))
		else:
			await h.trigger_strategy_discarded(player_id, card)
	return card




func destroy_base_strategies_on_invasion(to_zone: int, deferred_entries: Variant = null) -> void:
	## Destroy all <Base> strategy cards when any monster invades into zones 6-8 (12.9.2).
	## Checks both players' strategy zones. Uses discard_strategy_from_zone for replacement effects.
	## When deferred_entries is provided, strategy_discarded triggers are collected there
	## instead of resolving immediately.
	if to_zone < 6:
		return
	for pid in range(2):
		var player := game_state.players[pid]
		for i in range(player.strategy_zones.size() - 1, -1, -1):
			if not player.strategy_zones[i].is_empty() and h.is_base_strategy(player.strategy_zones[i]):
				# Rule-driven invasion destruction (12.9.2) — bypass protection.
				await discard_strategy_from_zone(pid, i, deferred_entries, true)
