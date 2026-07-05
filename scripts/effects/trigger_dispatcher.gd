class_name TriggerDispatcher
extends EffectModule

## Dispatches CardEffect trigger methods across active cards:
## iterates monster / zone tops / strategies, consults the registry and
## TRIGGER_FILTERS gates, builds contexts, and feeds the StandbyResolver.



func _passes_trigger_filter(filter: Dictionary, player_id: int, old_value: int, new_value: int) -> bool:
	return TriggerFilters.passes_basic(filter, game_state.current_phase, game_state.current_player_id == player_id, old_value, new_value)




# --- Trigger dispatchers ---

func _passes_enter_filter(card_data: Dictionary) -> bool:
	## Evaluate TRIGGER_FILTERS["on_enter"].
	## "played_from_hand": bool — gate by how the card entered play. true =
	##   only fire when played from hand (matches "if played from hand" rule
	##   text); false = only when entered via an effect (search / evolution /
	##   discard / etc.). Reads `card_data["played_from_effect"]` (set by
	##   trigger_enter) and inverts it for the filter API.
	return TriggerFilters.passes_enter(get_trigger_filter(card_data, "on_enter"), card_data.get("played_from_effect", false))




func trigger_enter(player_id: int, card_data: Dictionary, from_effect: bool = false) -> void:
	## Trigger <Enter> effect on the card that just entered play.
	## If from_effect is true, marks the card so enter effects know it wasn't played from hand.
	## If inside standby resolution, defers the enter to the pending queue (10.4.3).
	if from_effect:
		card_data["played_from_effect"] = true
	if not has_trigger(card_data, "on_enter"):
		return
	if not _passes_enter_filter(card_data):
		return
	var effect := get_effect(card_data)
	if not effect:
		return

	# Defer if inside standby resolution or nested inside another effect's execution.
	# This ensures e.g. multiple evolutions from one effect all complete before any
	# of the evolved cards' enters resolve.
	if _in_standby_resolution or not _active_effect_card.is_empty():
		_pending_standby_entries.append({
			"player_id": player_id,
			"card_data": card_data,
			"callback": effect.on_enter.bind(_build_context(player_id, card_data))
		})
		return

	_set_active_effect(player_id, card_data)
	# CardEffect.on_enter is non-coroutine in the base, but per-card overrides may be — await is required.
	@warning_ignore("redundant_await")
	await effect.on_enter(_build_context(player_id, card_data))
	_clear_active_effect()

	# Drain any entries that accumulated during this enter effect (e.g. from
	# perform_evolution or play_from_discard called within on_enter).
	while not _pending_standby_entries.is_empty():
		var batch: Array = _pending_standby_entries
		_pending_standby_entries = []
		await _resolve_standby_entries(batch)




func trigger_when_invading(player_id: int, from_zone: int, to_zone: int) -> void:
	## Trigger <When Invading> on the current monster card.
	var player := game_state.players[player_id]
	var effect := get_effect(player.current_monster)
	if effect:
		_set_active_effect(player_id, player.current_monster)
		@warning_ignore("redundant_await")
		await effect.on_when_invading(_build_context(player_id, player.current_monster), from_zone, to_zone)
		_clear_active_effect()




func collect_when_invading_entries(player_id: int, from_zone: int, to_zone: int) -> Array:
	## Collect <When Invading> entry for deferred resolution after movement completes.
	var entries: Array = []
	var player := game_state.players[player_id]
	if has_trigger(player.current_monster, "on_when_invading"):
		var effect := get_effect(player.current_monster)
		var ctx := _build_context(player_id, player.current_monster)
		# Capture zone state before crush resolves (for effects that check zone occupancy)
		var zone_idx := to_zone - 1
		if zone_idx >= 0 and zone_idx < 8:
			ctx.metadata["zone_had_card"] = player.zone_has_cards(zone_idx)
		entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": effect.on_when_invading.bind(ctx, from_zone, to_zone)})
	return entries




func trigger_crush(player_id: int, card_data: Dictionary) -> void:
	## Trigger crush effect on a card being destroyed by the crush rule.
	var effect := get_effect(card_data)
	if effect:
		var saved_player_id: int = _active_effect_player_id
		var saved_card: Dictionary = _active_effect_card
		_set_active_effect(player_id, card_data)
		@warning_ignore("redundant_await")
		await effect.on_crush(_build_context(player_id, card_data))
		if saved_card.is_empty():
			_clear_active_effect()
		else:
			_set_active_effect(saved_player_id, saved_card)




func trigger_revenge(player_id: int, card_data: Dictionary) -> void:
	## Trigger <Revenge> on a card being destroyed by an effect.
	var effect := get_effect(card_data)
	if effect and has_trigger(card_data, "on_revenge"):
		h.log_message.emit(GameLog.revenge_triggered(player_id, card_data.get("id", "")))
		var saved_player_id: int = _active_effect_player_id
		var saved_card: Dictionary = _active_effect_card
		_set_active_effect(player_id, card_data)
		@warning_ignore("redundant_await")
		await effect.on_revenge(_build_context(player_id, card_data))
		if saved_card.is_empty():
			_clear_active_effect()
		else:
			_set_active_effect(saved_player_id, saved_card)




func collect_crush_and_revenge_entries(player_id: int, card_data: Dictionary) -> Array:
	## Collect crush and revenge entries for deferred resolution after movement.
	## These entries use skip_active_check since the card is already in the discard pile.
	## When a card has both on_crush and on_revenge, they are merged into a single entry
	## so the card only appears once in standby choice prompts.
	var entries: Array = []
	var has_crush := has_trigger(card_data, "on_crush")
	var has_revenge := has_trigger(card_data, "on_revenge")
	if has_crush and has_revenge:
		var effect := get_effect(card_data)
		var ctx := _build_context(player_id, card_data)
		var combined_cb := func():
			@warning_ignore("redundant_await")
			await effect.on_crush(ctx)
			h.log_message.emit(GameLog.revenge_triggered(player_id, card_data.get("id", "")))
			@warning_ignore("redundant_await")
			await effect.on_revenge(ctx)
		entries.append({"player_id": player_id, "card_data": card_data, "callback": combined_cb, "skip_active_check": true})
	elif has_crush:
		var effect := get_effect(card_data)
		var ctx := _build_context(player_id, card_data)
		entries.append({"player_id": player_id, "card_data": card_data, "callback": effect.on_crush.bind(ctx), "skip_active_check": true})
	elif has_revenge:
		var effect := get_effect(card_data)
		var ctx := _build_context(player_id, card_data)
		var revenge_cb := func():
			h.log_message.emit(GameLog.revenge_triggered(player_id, card_data.get("id", "")))
			@warning_ignore("redundant_await")
			await effect.on_revenge(ctx)
		entries.append({"player_id": player_id, "card_data": card_data, "callback": revenge_cb, "skip_active_check": true})
	return entries




func _passes_discard_from_hand_filter(card_data: Dictionary, player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["on_discard_from_hand"] for the discarded card's
	## self-trigger. The discard may happen on either player's turn, so the
	## relevant gate is who *caused* the discard, not whose turn it is.
	## "caused_by_opponent": bool — true = fire only when an opponent effect caused
	##   the discard (e.g. EBP04-046 Rodan); false = fire only when the owner's own
	##   effect caused it. Rules-based discards (no active effect) match neither
	##   value, so the trigger is skipped under either setting.
	## "own_turn": bool — secondary gate by the card owner's turn ownership.
	return TriggerFilters.passes_discard_from_hand(
		get_trigger_filter(card_data, "on_discard_from_hand"),
		game_state.current_player_id == player_id, _active_effect_player_id, player_id)


func _passes_discard_condition(effect: CardEffect, card_data: Dictionary, ctx: EffectContext) -> bool:
	## Card-specific trigger-time gate (e.g. EBP03-067's 2-color check), checked
	## once at discard time; NOT re-evaluated when a deferred entry resolves.
	if not has_trigger(card_data, "discard_from_hand_condition"):
		return true
	return effect.discard_from_hand_condition(ctx)




func trigger_discard_from_hand(player_id: int, card_data: Dictionary) -> void:
	## Trigger discard-from-hand effect on the card being discarded.
	if not _passes_discard_from_hand_filter(card_data, player_id):
		return
	var effect := get_effect(card_data)
	if effect:
		var ctx := _build_context(player_id, card_data)
		if not _passes_discard_condition(effect, card_data, ctx):
			return
		var saved_player_id: int = _active_effect_player_id
		var saved_card: Dictionary = _active_effect_card
		_set_active_effect(player_id, card_data)
		@warning_ignore("redundant_await")
		await effect.on_discard_from_hand(ctx)
		if saved_card.is_empty():
			_clear_active_effect()
		else:
			_set_active_effect(saved_player_id, saved_card)




func collect_discard_from_hand_entries(player_id: int, card_data: Dictionary) -> Array:
	## Collect discard-from-hand entry for deferred resolution (e.g. during invasion).
	var entries: Array = []
	if has_trigger(card_data, "on_discard_from_hand") and _passes_discard_from_hand_filter(card_data, player_id):
		var effect := get_effect(card_data)
		var ctx := _build_context(player_id, card_data)
		if _passes_discard_condition(effect, card_data, ctx):
			entries.append({"player_id": player_id, "card_data": card_data, "callback": effect.on_discard_from_hand.bind(ctx), "skip_active_check": true})
	return entries




func trigger_hand_cards_discarded_batch(player_id: int, cards: Array) -> void:
	## Standby-resolve on_discard_from_hand and on_hand_card_discarded for a
	## set of cards discarded simultaneously, per rule 10.4.3. Bundling all
	## entries into one batch lets the player choose resolution order when
	## multiple cards trigger at once (e.g. discarding two EBP04-046 Rodans
	## from hand).
	if cards.is_empty():
		return
	var entries: Array = []
	for card in cards:
		entries.append_array(collect_discard_from_hand_entries(player_id, card))
		entries.append_array(collect_hand_card_discarded_entries(player_id, card))
	if not entries.is_empty():
		await _resolve_standby_entries(entries)




func collect_discarded_for_invasion_entries(player_id: int, card_data: Dictionary) -> Array:
	## Collect discarded-for-invasion entry for deferred resolution during invasion.
	## The callback checks on_discarded_for_invasion and plays from discard if true.
	var entries: Array = []
	if has_trigger(card_data, "on_discarded_for_invasion"):
		entries.append({"player_id": player_id, "card_data": card_data, "callback": _resolve_discarded_for_invasion.bind(player_id, card_data), "skip_active_check": true})
	return entries




func _resolve_discarded_for_invasion(player_id: int, card_data: Dictionary) -> void:
	var effect := get_effect(card_data)
	if effect:
		var ctx := _build_context(player_id, card_data)
		if effect.on_discarded_for_invasion(ctx):
			await h.play_from_discard(player_id, card_data)




func trigger_burst_discard(player_id: int, card_data: Dictionary) -> void:
	## Trigger on_burst_discard on the Burst monster being discarded at end of turn.
	var effect := get_effect(card_data)
	if effect:
		_set_active_effect(player_id, card_data)
		@warning_ignore("redundant_await")
		await effect.on_burst_discard(_build_context(player_id, card_data))
		_clear_active_effect()




func trigger_rage_changed(player_id: int, old_rage: int, new_rage: int) -> void:
	## Trigger rage changed on all active cards for this player (monster + zones + strategies).
	## Collects all applicable effects, then resolves with rule action checks between each.
	## Each candidate is gated through TRIGGER_FILTERS (phase / own_turn / direction).
	var entries: Array = []
	var player := game_state.players[player_id]

	# Monster card
	if has_trigger(player.current_monster, "on_rage_changed"):
		var filter := get_trigger_filter(player.current_monster, "on_rage_changed")
		if _passes_trigger_filter(filter, player_id, old_rage, new_rage):
			var me := get_effect(player.current_monster)
			var ctx := _build_context(player_id, player.current_monster)
			entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_rage_changed.bind(ctx, old_rage, new_rage)})

	# Battle cards in zones (top card only — stacked cards are inactive per 12.7.3)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_rage_changed"):
			var filter := get_trigger_filter(zone_card, "on_rage_changed")
			if _passes_trigger_filter(filter, player_id, old_rage, new_rage):
				var ze := get_effect(zone_card)
				var ctx := _build_context(player_id, zone_card)
				entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_rage_changed.bind(ctx, old_rage, new_rage)})

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_rage_changed"):
			var filter := get_trigger_filter(sz_card, "on_rage_changed")
			if _passes_trigger_filter(filter, player_id, old_rage, new_rage):
				var se := get_effect(sz_card)
				var ctx := _build_context(player_id, sz_card)
				entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_rage_changed.bind(ctx, old_rage, new_rage)})

	# Also trigger on_opponent_rage_changed on the OTHER player's cards
	var opp_id: int = 1 - player_id
	var opp := game_state.players[opp_id]
	var opp_entries: Array = []

	if has_trigger(opp.current_monster, "on_opponent_rage_changed"):
		var filter := get_trigger_filter(opp.current_monster, "on_opponent_rage_changed")
		if _passes_trigger_filter(filter, opp_id, old_rage, new_rage):
			var me := get_effect(opp.current_monster)
			var ctx := _build_context(opp_id, opp.current_monster)
			opp_entries.append({"player_id": opp_id, "card_data": opp.current_monster, "callback": me.on_opponent_rage_changed.bind(ctx, old_rage, new_rage)})

	for i in range(8):
		var zone_card := opp.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_opponent_rage_changed"):
			var filter := get_trigger_filter(zone_card, "on_opponent_rage_changed")
			if _passes_trigger_filter(filter, opp_id, old_rage, new_rage):
				var ze := get_effect(zone_card)
				var ctx := _build_context(opp_id, zone_card)
				opp_entries.append({"player_id": opp_id, "card_data": zone_card, "callback": ze.on_opponent_rage_changed.bind(ctx, old_rage, new_rage)})

	for sz_card in opp.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_opponent_rage_changed"):
			var filter := get_trigger_filter(sz_card, "on_opponent_rage_changed")
			if _passes_trigger_filter(filter, opp_id, old_rage, new_rage):
				var se := get_effect(sz_card)
				var ctx := _build_context(opp_id, sz_card)
				opp_entries.append({"player_id": opp_id, "card_data": sz_card, "callback": se.on_opponent_rage_changed.bind(ctx, old_rage, new_rage)})

	entries.append_array(opp_entries)
	await _resolve_standby_entries(entries)




func trigger_monster_advance(player_id: int, from_zone: int, to_zone: int) -> void:
	## Trigger monster advance on all active cards for this player.
	## Collects all applicable effects, then resolves with rule action checks between each.
	var entries: Array = []
	var player := game_state.players[player_id]

	# Monster card itself
	if has_trigger(player.current_monster, "on_monster_advance"):
		var me := get_effect(player.current_monster)
		var ctx := _build_context(player_id, player.current_monster)
		entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_monster_advance.bind(ctx, from_zone, to_zone)})

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_monster_advance"):
			var ze := get_effect(zone_card)
			var ctx := _build_context(player_id, zone_card)
			entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_monster_advance.bind(ctx, from_zone, to_zone)})

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_monster_advance"):
			var se := get_effect(sz_card)
			var ctx := _build_context(player_id, sz_card)
			entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_monster_advance.bind(ctx, from_zone, to_zone)})

	await _resolve_standby_entries(entries)




func collect_monster_advance_entries(player_id: int, from_zone: int, to_zone: int) -> Array:
	## Collect monster advance entries for deferred resolution after movement completes.
	var entries: Array = []
	var player := game_state.players[player_id]

	if has_trigger(player.current_monster, "on_monster_advance"):
		var me := get_effect(player.current_monster)
		var ctx := _build_context(player_id, player.current_monster)
		entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_monster_advance.bind(ctx, from_zone, to_zone)})

	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_monster_advance"):
			var ze := get_effect(zone_card)
			var ctx := _build_context(player_id, zone_card)
			entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_monster_advance.bind(ctx, from_zone, to_zone)})

	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_monster_advance"):
			var se := get_effect(sz_card)
			var ctx := _build_context(player_id, sz_card)
			entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_monster_advance.bind(ctx, from_zone, to_zone)})

	return entries




func trigger_phase_start(phase: CardEnums.GamePhase) -> void:
	## Trigger phase start on all active cards for both players.
	## Per 10.4.3.2-10.4.3.3: turn player's abilities resolve first.
	var entries: Array = []
	for player_id in range(2):
		entries.append_array(_collect_phase_entries(player_id, phase, true))
	await _resolve_standby_entries(entries)




func trigger_phase_end(phase: CardEnums.GamePhase) -> void:
	## Trigger phase end on all active cards for both players.
	## Per 10.4.3.2-10.4.3.3: turn player's abilities resolve first.
	var entries: Array = []
	for player_id in range(2):
		entries.append_array(_collect_phase_entries(player_id, phase, false))
	await _resolve_standby_entries(entries)




func _passes_phase_filter(card_data: Dictionary, method_name: String, player_id: int, phase: CardEnums.GamePhase) -> bool:
	## Check if a card's TRIGGER_FILTERS[method_name] entry matches the given
	## phase and turn ownership. method_name is "on_phase_start" or "on_phase_end".
	return TriggerFilters.passes_phase(get_trigger_filter(card_data, method_name), phase, game_state.current_player_id == player_id)




func _collect_phase_entries(player_id: int, phase: CardEnums.GamePhase, is_start: bool) -> Array:
	## Collect standby entries for phase triggers from all active cards of a player.
	## Only includes cards whose effect script overrides the method AND passes the phase filter.
	var entries: Array = []
	var player := game_state.players[player_id]
	var method_name: String = "on_phase_start" if is_start else "on_phase_end"

	# Monster card
	if has_trigger(player.current_monster, method_name):
		var me := get_effect(player.current_monster)
		if _passes_phase_filter(player.current_monster, method_name, player_id, phase):
			var ctx := _build_context(player_id, player.current_monster)
			var method: Callable = me.on_phase_start if is_start else me.on_phase_end
			entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": method.bind(ctx, phase)})

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, method_name):
			var ze := get_effect(zone_card)
			if _passes_phase_filter(zone_card, method_name, player_id, phase):
				var ctx := _build_context(player_id, zone_card)
				var method: Callable = ze.on_phase_start if is_start else ze.on_phase_end
				entries.append({"player_id": player_id, "card_data": zone_card, "callback": method.bind(ctx, phase)})

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, method_name):
			var se := get_effect(sz_card)
			if _passes_phase_filter(sz_card, method_name, player_id, phase):
				var ctx := _build_context(player_id, sz_card)
				var method: Callable = se.on_phase_start if is_start else se.on_phase_end
				entries.append({"player_id": player_id, "card_data": sz_card, "callback": method.bind(ctx, phase)})

	return entries




func _resolve_discard_play(player_id: int, card_data: Dictionary, is_optional: bool) -> void:
	## Play a card from discard via on-monster-played trigger. For optional
	## ('may play') effects, route through play_from_discard_or_skip so the
	## prompt is the standard "Play <card> from discard to a zone (or skip)"
	## zone-picker rather than a Yes/No choice. Mandatory plays use
	## play_from_discard directly (auto-picks zone, no skip).
	var placed_zone: int
	if is_optional:
		var card_name: String = card_data.get("name", "Unknown")
		placed_zone = await h.play_from_discard_or_skip(
			player_id, card_data, tr("STR_EFF_PLACE_DISCARD_FMT") % card_name)
	else:
		placed_zone = await h.play_from_discard(player_id, card_data)
	if placed_zone >= 0:
		await trigger_battle_card_played(player_id, card_data, placed_zone)




func trigger_monster_played(player_id: int, old_monster: Dictionary, new_monster: Dictionary, discard_snapshot: Array = []) -> void:
	## Trigger on_monster_played on all active cards for this player.
	## Collects all applicable effects, then resolves with rule action checks between each.
	## `discard_snapshot` should be the discard pile captured BEFORE the new
	## monster's on_enter ran — cards milled into discard during enter (e.g.
	## EBP02-048 King Ghidorah 1991's mill 3) shouldn't qualify for
	## can_play_from_discard_on_monster_played because they weren't there to
	## "see" the monster get played. Empty array = use the current pile.
	var entries: Array = []
	var player := game_state.players[player_id]
	var triggered_ids: Array[String] = []

	# Battle cards in zones (top card only)
	# Track triggered IDs because effects can move cards to new zones during iteration.
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_monster_played"):
			var card_id: String = zone_card.get("id", "")
			if card_id in triggered_ids:
				continue
			triggered_ids.append(card_id)
			var ze := get_effect(zone_card)
			var ctx := _build_context(player_id, zone_card)
			entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_monster_played.bind(ctx, old_monster, new_monster)})

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_monster_played"):
			var se := get_effect(sz_card)
			var ctx := _build_context(player_id, sz_card)
			entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_monster_played.bind(ctx, old_monster, new_monster)})

	await _resolve_standby_entries(entries)

	# Check discard pile for cards that can play from discard on monster played.
	# Use the pre-enter snapshot when provided so newly-milled cards don't
	# retroactively qualify. Filter to cards that are still in the live discard
	# (so something an effect already removed doesn't try to play).
	var pool: Array = discard_snapshot if not discard_snapshot.is_empty() else player.discard_pile.duplicate()
	var discard_entries: Array = []
	for discard_card in pool:
		if not discard_card in player.discard_pile:
			continue
		var de := get_effect(discard_card)
		if de:
			var ctx := _build_context(player_id, discard_card)
			if de.can_play_from_discard_on_monster_played(ctx):
				var optional: bool = de.is_discard_play_optional()
				discard_entries.append({"player_id": player_id, "card_data": discard_card, "callback": _resolve_discard_play.bind(player_id, discard_card, optional)})

	await _resolve_standby_entries(discard_entries)




func _passes_battle_card_played_filter(card_data: Dictionary, watcher_player_id: int, played_player_id: int, played_from_deck: bool) -> bool:
	## Evaluate TRIGGER_FILTERS["on_battle_card_played"] for battle-card-played triggers.
	## "own_turn": bool — gate by watcher's turn ownership (false = opponent's turn).
	## "played_by_opponent": bool — gate by who played the card; true = only when
	##                              the watcher's opponent played it. Use this
	##                              instead of own_turn for "your opponent plays..."
	##                              wording, since opponents can play cards on
	##                              your turn via certain effects.
	## "played_from_deck": bool — true = only when the played card came from the deck;
	##                            false = only when NOT from the deck (i.e. from hand/discard).
	return TriggerFilters.passes_battle_card_played(
		get_trigger_filter(card_data, "on_battle_card_played"),
		game_state.current_player_id == watcher_player_id,
		played_player_id != watcher_player_id, played_from_deck)




func trigger_battle_card_played(player_id: int, card_data: Dictionary, zone_index: int, played_from_deck: bool = false) -> void:
	## Trigger on_battle_card_played on all active cards from both players.
	## played_from_deck: true when the card was played directly from the deck (e.g. via a deck-dig effect).
	## Both sides are checked so opponent-watching effects (e.g. EBP04-028 Gigan) fire correctly.
	var entries: Array = []
	var player := game_state.players[player_id]
	var opponent_id: int = 1 - player_id
	var opponent := game_state.players[opponent_id]
	var played_id: String = card_data.get("id", "")

	# Own monster card
	if has_trigger(player.current_monster, "on_battle_card_played"):
		if _passes_battle_card_played_filter(player.current_monster, player_id, player_id, played_from_deck):
			var me := get_effect(player.current_monster)
			var ctx := _build_context(player_id, player.current_monster)
			entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_battle_card_played.bind(ctx, zone_index, played_from_deck)})

	# Own strategy cards (e.g. EBP02-073 Bloody Chainsaw — <Your Turn> effect)
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_battle_card_played"):
			if _passes_battle_card_played_filter(sz_card, player_id, player_id, played_from_deck):
				var se := get_effect(sz_card)
				var ctx := _build_context(player_id, sz_card)
				entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_battle_card_played.bind(ctx, zone_index, played_from_deck)})

	# Own battle cards in zones (top card only, skip the card that was just played)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("id", "") != played_id and has_trigger(zone_card, "on_battle_card_played"):
			if _passes_battle_card_played_filter(zone_card, player_id, player_id, played_from_deck):
				var ze := get_effect(zone_card)
				var ctx := _build_context(player_id, zone_card)
				entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_battle_card_played.bind(ctx, zone_index, played_from_deck)})

	# Opponent monster card (e.g. EBP04-028 Gigan — <Opponent's Turn> effect)
	if has_trigger(opponent.current_monster, "on_battle_card_played"):
		if _passes_battle_card_played_filter(opponent.current_monster, opponent_id, player_id, played_from_deck):
			var ome := get_effect(opponent.current_monster)
			var octx := _build_context(opponent_id, opponent.current_monster)
			entries.append({"player_id": opponent_id, "card_data": opponent.current_monster, "callback": ome.on_battle_card_played.bind(octx, zone_index, played_from_deck)})

	# Opponent strategy cards
	for sz_card in opponent.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_battle_card_played"):
			if _passes_battle_card_played_filter(sz_card, opponent_id, player_id, played_from_deck):
				var se := get_effect(sz_card)
				var ctx := _build_context(opponent_id, sz_card)
				entries.append({"player_id": opponent_id, "card_data": sz_card, "callback": se.on_battle_card_played.bind(ctx, zone_index, played_from_deck)})

	# Opponent battle cards in zones (top card only)
	for i in range(8):
		var zone_card := opponent.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_battle_card_played"):
			if _passes_battle_card_played_filter(zone_card, opponent_id, player_id, played_from_deck):
				var ze := get_effect(zone_card)
				var ctx := _build_context(opponent_id, zone_card)
				entries.append({"player_id": opponent_id, "card_data": zone_card, "callback": ze.on_battle_card_played.bind(ctx, zone_index, played_from_deck)})

	await _resolve_standby_entries(entries)




func _passes_hand_discarded_filter(card_data: Dictionary, watcher_player_id: int, discarded_card: Dictionary) -> bool:
	## Evaluate TRIGGER_FILTERS["on_hand_card_discarded"] for hand-discard triggers.
	## "card_type": "battle" | "strategy" | "monster" — discarded card's type must match.
	## "own_turn": bool — gate by watcher's turn ownership (false = opponent's turn).
	return TriggerFilters.passes_hand_discarded(
		get_trigger_filter(card_data, "on_hand_card_discarded"),
		game_state.current_player_id == watcher_player_id, discarded_card)




func trigger_hand_card_discarded(player_id: int, card_data: Dictionary) -> void:
	## Trigger on ALL active cards when a card is discarded from the owner's hand.
	## Collects all applicable effects, then resolves with rule action checks between each.
	await _resolve_standby_entries(collect_hand_card_discarded_entries(player_id, card_data))




func collect_hand_card_discarded_entries(player_id: int, card_data: Dictionary) -> Array:
	## Collect hand-card-discarded entries for deferred resolution (e.g. during invasion).
	var entries: Array = []
	var player := game_state.players[player_id]

	# Monster card
	if has_trigger(player.current_monster, "on_hand_card_discarded"):
		if _passes_hand_discarded_filter(player.current_monster, player_id, card_data):
			var me := get_effect(player.current_monster)
			var ctx := _build_context(player_id, player.current_monster)
			entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_hand_card_discarded.bind(ctx, card_data)})

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_hand_card_discarded"):
			if _passes_hand_discarded_filter(zone_card, player_id, card_data):
				var ze := get_effect(zone_card)
				var ctx := _build_context(player_id, zone_card)
				entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_hand_card_discarded.bind(ctx, card_data)})

	# Strategy cards
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_hand_card_discarded"):
			if _passes_hand_discarded_filter(sz_card, player_id, card_data):
				var se := get_effect(sz_card)
				var ctx := _build_context(player_id, sz_card)
				entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_hand_card_discarded.bind(ctx, card_data)})

	return entries




func trigger_counter_success(counterer_player_id: int, countered_player_id: int) -> void:
	## Trigger when a counter succeeds (CP >= threat). Collects:
	##   - on_counter_success on all active cards for the counterer (the player whose
	##     CP overcame the opponent's threat — i.e. the turn player in this game)
	##   - on_self_countered on the countered player's monster card (the one whose
	##     monster retreats and ranks up — the opponent in this game)
	## Resolves with rule action checks between each ability.
	var entries: Array = []
	var counterer := game_state.players[counterer_player_id]

	# Counterer side — "When you successfully counter your opponent's monster" cards
	if has_trigger(counterer.current_monster, "on_counter_success"):
		var me := get_effect(counterer.current_monster)
		var ctx := _build_context(counterer_player_id, counterer.current_monster)
		entries.append({"player_id": counterer_player_id, "card_data": counterer.current_monster, "callback": me.on_counter_success.bind(ctx)})

	for i in range(8):
		var zone_card := counterer.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_counter_success"):
			var ze := get_effect(zone_card)
			var ctx := _build_context(counterer_player_id, zone_card)
			entries.append({"player_id": counterer_player_id, "card_data": zone_card, "callback": ze.on_counter_success.bind(ctx)})

	for sz_card in counterer.strategy_zones:
		if not sz_card.is_empty() and has_trigger(sz_card, "on_counter_success"):
			var se := get_effect(sz_card)
			var ctx := _build_context(counterer_player_id, sz_card)
			entries.append({"player_id": counterer_player_id, "card_data": sz_card, "callback": se.on_counter_success.bind(ctx)})

	# Countered side — only the monster card itself gets "countered" (battle cards aren't)
	var countered := game_state.players[countered_player_id]
	if has_trigger(countered.current_monster, "on_self_countered"):
		var cme := get_effect(countered.current_monster)
		var cctx := _build_context(countered_player_id, countered.current_monster)
		entries.append({"player_id": countered_player_id, "card_data": countered.current_monster, "callback": cme.on_self_countered.bind(cctx)})

	await _resolve_standby_entries(entries)




func _collect_strategy_discarded_entries_inner(player_id: int, strategy_card: Dictionary) -> Array:
	var entries: Array = []
	var player := game_state.players[player_id]
	var discarded_id: String = strategy_card.get("id", "")

	# Self-trigger: the card being discarded reacts to its own discard.
	# It's already in the discard pile so skip_active_check bypasses the
	# "card still in play" filter on standby resolution.
	if has_trigger(strategy_card, "on_strategy_discarded"):
		var ds := get_effect(strategy_card)
		var dctx := _build_context(player_id, strategy_card)
		entries.append({
			"player_id": player_id,
			"card_data": strategy_card,
			"callback": ds.on_strategy_discarded.bind(dctx, strategy_card),
			"skip_active_check": true,
		})

	# Monster card
	if has_trigger(player.current_monster, "on_strategy_discarded"):
		var me := get_effect(player.current_monster)
		var ctx := _build_context(player_id, player.current_monster)
		entries.append({"player_id": player_id, "card_data": player.current_monster, "callback": me.on_strategy_discarded.bind(ctx, strategy_card)})

	# Battle cards in zones (top card only)
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if not zone_card.is_empty() and has_trigger(zone_card, "on_strategy_discarded"):
			var ze := get_effect(zone_card)
			var ctx := _build_context(player_id, zone_card)
			entries.append({"player_id": player_id, "card_data": zone_card, "callback": ze.on_strategy_discarded.bind(ctx, strategy_card)})

	# Strategy cards (skip the just-discarded card; it's already handled by self-trigger)
	for sz_card in player.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("id", "") != discarded_id and has_trigger(sz_card, "on_strategy_discarded"):
			var se := get_effect(sz_card)
			var ctx := _build_context(player_id, sz_card)
			entries.append({"player_id": player_id, "card_data": sz_card, "callback": se.on_strategy_discarded.bind(ctx, strategy_card)})

	return entries




func trigger_strategy_discarded(player_id: int, strategy_card: Dictionary) -> void:
	## Trigger on the discarded card itself + ALL active cards when a strategy
	## is sent from strategy zone to discard. Collects all applicable effects,
	## then resolves with rule action checks between each.
	await _resolve_standby_entries(_collect_strategy_discarded_entries_inner(player_id, strategy_card))




func collect_strategy_discarded_entries(player_id: int, strategy_card: Dictionary) -> Array:
	## Collect on_strategy_discarded entries for deferred resolution (e.g. during invasion).
	return _collect_strategy_discarded_entries_inner(player_id, strategy_card)




func _passes_invasion_observed_filter(card_data: Dictionary, player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["on_invasion_observed"] for an observer card.
	## "own_turn": bool — gate by the watcher's turn ownership.
	return TriggerFilters.passes_own_turn(get_trigger_filter(card_data, "on_invasion_observed"), game_state.current_player_id == player_id)




func trigger_invasion_observed(invading_player_id: int, from_zone: int, to_zone: int) -> void:
	## Trigger on ALL active cards for BOTH players when a monster invades.
	## Per 10.4.3.2-10.4.3.3: turn player's abilities resolve first.
	## Collects all applicable effects, then resolves with rule action checks between each.
	var entries: Array = []
	for pid in range(2):
		var player := game_state.players[pid]

		# Monster card
		if has_trigger(player.current_monster, "on_invasion_observed") \
				and _passes_invasion_observed_filter(player.current_monster, pid):
			var me := get_effect(player.current_monster)
			var ctx := _build_context(pid, player.current_monster)
			entries.append({"player_id": pid, "card_data": player.current_monster, "callback": me.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

		# Battle cards in zones (top card only)
		for i in range(8):
			var zone_card := player.get_zone_top_card(i)
			if not zone_card.is_empty() and has_trigger(zone_card, "on_invasion_observed") \
					and _passes_invasion_observed_filter(zone_card, pid):
				var ze := get_effect(zone_card)
				var ctx := _build_context(pid, zone_card)
				entries.append({"player_id": pid, "card_data": zone_card, "callback": ze.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

		# Strategy cards
		for sz_card in player.strategy_zones:
			if not sz_card.is_empty() and has_trigger(sz_card, "on_invasion_observed") \
					and _passes_invasion_observed_filter(sz_card, pid):
				var se := get_effect(sz_card)
				var ctx := _build_context(pid, sz_card)
				entries.append({"player_id": pid, "card_data": sz_card, "callback": se.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

	await _resolve_standby_entries(entries)




func collect_invasion_observed_entries(invading_player_id: int, from_zone: int, to_zone: int) -> Array:
	## Collect invasion observed entries for deferred resolution after movement completes.
	var entries: Array = []
	for pid in range(2):
		var player := game_state.players[pid]

		if has_trigger(player.current_monster, "on_invasion_observed") \
				and _passes_invasion_observed_filter(player.current_monster, pid):
			var me := get_effect(player.current_monster)
			var ctx := _build_context(pid, player.current_monster)
			entries.append({"player_id": pid, "card_data": player.current_monster, "callback": me.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

		for i in range(8):
			var zone_card := player.get_zone_top_card(i)
			if not zone_card.is_empty() and has_trigger(zone_card, "on_invasion_observed") \
					and _passes_invasion_observed_filter(zone_card, pid):
				var ze := get_effect(zone_card)
				var ctx := _build_context(pid, zone_card)
				entries.append({"player_id": pid, "card_data": zone_card, "callback": ze.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

		for sz_card in player.strategy_zones:
			if not sz_card.is_empty() and has_trigger(sz_card, "on_invasion_observed") \
					and _passes_invasion_observed_filter(sz_card, pid):
				var se := get_effect(sz_card)
				var ctx := _build_context(pid, sz_card)
				entries.append({"player_id": pid, "card_data": sz_card, "callback": se.on_invasion_observed.bind(ctx, invading_player_id, from_zone, to_zone)})

	return entries




func trigger_leave_play(player_id: int, leaving_card: Dictionary, zone_index: int) -> void:
	## Fire on_leave_play for a card that just left a zone for any reason
	## (destroyed, overloaded, banished, returned to hand/deck). Distinct from
	## on_destroy/on_revenge, which only fire for <Destroy> actions per the
	## rules. Used by linked-card effects (e.g. EBP04-067 ↔ token).
	if leaving_card.is_empty():
		return
	if not has_trigger(leaving_card, "on_leave_play"):
		return
	var effect := get_effect(leaving_card)
	if effect:
		@warning_ignore("redundant_await")
		await effect.on_leave_play(_build_context(player_id, leaving_card), zone_index)




func trigger_all_monster_enter_abilities(player_id: int) -> void:
	## Re-trigger the on_enter ability of the topmost monster card. Used by EBP04-041 (The New Gotengo).
	var player := game_state.players[player_id]
	if player.current_monster.is_empty():
		return
	await trigger_enter(player_id, player.current_monster)




func collect_ally_zone_card_destroyed_entries(player_id: int, destroyed_card: Dictionary, zone_idx: int) -> Array:
	## Collect standby entries for on_ally_zone_card_destroyed triggers.
	## Iterates the destroying player's zone cards for cards with this trigger.
	var entries: Array = []
	var player := game_state.players[player_id]
	for i in range(8):
		var zone_card := player.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if zone_card.get("id", "") == destroyed_card.get("id", ""):
			continue  # Skip the card that was just destroyed
		if not has_trigger(zone_card, "on_ally_zone_card_destroyed"):
			continue
		if not _passes_zone_destroyed_filter(zone_card, "on_ally_zone_card_destroyed", player, zone_idx, false):
			continue
		var effect := get_effect(zone_card)
		if effect:
			var ctx := _build_context(player_id, zone_card)
			entries.append({"player_id": player_id, "card_data": zone_card, "callback": effect.on_ally_zone_card_destroyed.bind(ctx, destroyed_card, zone_idx)})
	return entries




func trigger_ally_zone_card_destroyed(player_id: int, destroyed_card: Dictionary, zone_idx: int) -> void:
	## Fire on_ally_zone_card_destroyed triggers for the player whose card was destroyed.
	var entries := collect_ally_zone_card_destroyed_entries(player_id, destroyed_card, zone_idx)
	if not entries.is_empty():
		await _resolve_standby_entries(entries)




func collect_opponent_zone_card_destroyed_entries(destroyed_player_id: int, destroyed_card: Dictionary, zone_idx: int) -> Array:
	## Collect standby entries for on_opponent_zone_card_destroyed triggers.
	## Iterates the opponent of the destroyed card's owner (they react when opponent's card is destroyed).
	var entries: Array = []
	var watcher_id: int = 1 - destroyed_player_id
	var watcher := game_state.players[watcher_id]
	var monster := watcher.current_monster
	if not monster.is_empty() and has_trigger(monster, "on_opponent_zone_card_destroyed"):
		if _passes_zone_destroyed_filter(monster, "on_opponent_zone_card_destroyed", watcher, zone_idx, true):
			var effect := get_effect(monster)
			if effect:
				var ctx := _build_context(watcher_id, monster)
				entries.append({"player_id": watcher_id, "card_data": monster, "callback": effect.on_opponent_zone_card_destroyed.bind(ctx, destroyed_card, zone_idx)})
	for i in range(8):
		var zone_card := watcher.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if not has_trigger(zone_card, "on_opponent_zone_card_destroyed"):
			continue
		if not _passes_zone_destroyed_filter(zone_card, "on_opponent_zone_card_destroyed", watcher, zone_idx, true):
			continue
		var effect := get_effect(zone_card)
		if effect:
			var ctx := _build_context(watcher_id, zone_card)
			entries.append({"player_id": watcher_id, "card_data": zone_card, "callback": effect.on_opponent_zone_card_destroyed.bind(ctx, destroyed_card, zone_idx)})
	return entries




func _passes_zone_destroyed_filter(card_data: Dictionary, method_name: String, watcher: PlayerState, zone_idx: int, is_cross_board: bool) -> bool:
	## Evaluate TRIGGER_FILTERS[method_name] for zone-card-destroyed triggers.
	## `column: "monster"` — destroyed zone must be in the watcher's monster column.
	## `is_cross_board` distinguishes ally (false, same side) vs opponent (true, cross-board).
	return TriggerFilters.passes_zone_destroyed(get_trigger_filter(card_data, method_name), watcher.monster_zone, zone_idx, is_cross_board)




func trigger_opponent_zone_card_destroyed(destroyed_player_id: int, destroyed_card: Dictionary, zone_idx: int) -> void:
	## Fire on_opponent_zone_card_destroyed triggers on the opponent of the destroyed card's owner.
	var entries := collect_opponent_zone_card_destroyed_entries(destroyed_player_id, destroyed_card, zone_idx)
	if not entries.is_empty():
		await _resolve_standby_entries(entries)




func _passes_card_returned_filter(card_data: Dictionary, watcher_player_id: int, returning_player_id: int) -> bool:
	## Evaluate TRIGGER_FILTERS["on_card_returned_from_discard"].
	## "own_turn": bool — gate by watcher's turn ownership.
	## "returned_by_opponent": bool — true = only when the watcher's opponent
	##                                returned the card.
	return TriggerFilters.passes_card_returned(
		get_trigger_filter(card_data, "on_card_returned_from_discard"),
		game_state.current_player_id == watcher_player_id, returning_player_id != watcher_player_id)




func collect_card_returned_from_discard_entries(returning_player_id: int, card: Dictionary) -> Array:
	## Collect standby entries for on_card_returned_from_discard triggers from
	## active cards on BOTH players. TRIGGER_FILTERS gates by turn / who returned.
	var entries: Array = []
	for pid in range(2):
		var observer := game_state.players[pid]
		for i in range(8):
			var zone_card := observer.get_zone_top_card(i)
			if zone_card.is_empty():
				continue
			if not has_trigger(zone_card, "on_card_returned_from_discard"):
				continue
			if not _passes_card_returned_filter(zone_card, pid, returning_player_id):
				continue
			var effect := get_effect(zone_card)
			if effect:
				var ctx := _build_context(pid, zone_card)
				entries.append({"callback": effect.on_card_returned_from_discard.bind(ctx, card), "player_id": pid, "card_data": zone_card})
	return entries




func trigger_card_returned_from_discard(returning_player_id: int, card: Dictionary) -> void:
	## Fire on_card_returned_from_discard triggers when a player returns a card from discard to hand.
	var entries := collect_card_returned_from_discard_entries(returning_player_id, card)
	if not entries.is_empty():
		await _resolve_standby_entries(entries)
