class_name ActionHandler
extends RefCounted

## Executes game actions by mutating GameState. Assumes validation has already passed.

signal battle_card_played(player_id: int, card: Dictionary, zone_index: int)
signal strategy_card_played(player_id: int, card: Dictionary, strategy_index: int)
signal monster_advanced(player_id: int, from_zone: int, to_zone: int)
signal rage_gained(player_id: int, new_rage: int)
signal card_discarded(player_id: int, card: Dictionary)
signal monster_played(player_id: int, old_monster: Dictionary, new_monster: Dictionary)
signal monster_countered(player_id: int, old_monster: Dictionary, new_monster: Dictionary)
signal battle_card_crushed(player_id: int, zone_index: int, card: Dictionary)
signal cards_drawn(player_id: int, count: int)
signal strategy_cleared(player_id: int, cards: Array)
signal counter_failed(player_id: int, total_cp: int, threat: int)
signal counter_succeeded(player_id: int, total_cp: int, threat: int)
signal counter_immunity_triggered(player_id: int, total_cp: int, threshold: int)
signal counter_prevented(player_id: int)
signal play_cancelled(player_id: int)
signal monster_rankup_requested(player_id: int, monsters: Array[Dictionary], valid_indices: Array[int], prompt: String)

var effect_handler: EffectHandler
var _monster_rankup_result: int = -1
signal _monster_rankup_resolved


func execute(action: CardEnums.ActionType, params: Dictionary, state: GameState) -> void:
	match action:
		CardEnums.ActionType.PLAY_BATTLE:
			await _play_battle_card(params["hand_index"], params["zone_index"], state)
		CardEnums.ActionType.PLAY_STRATEGY:
			await _play_strategy_card(params["hand_index"], state)
		CardEnums.ActionType.GAIN_RAGE:
			await _gain_rage(params["hand_index"], state)
		CardEnums.ActionType.PLAY_MONSTER:
			await _play_monster(params["hand_index"], state)
		CardEnums.ActionType.INVADE:
			await _invade(params["hand_index"], state)


func execute_start_phase_draw(state: GameState) -> void:
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()
	var draw_count: int = opponent.get_monster_rank()
	player.draw_cards(draw_count)
	cards_drawn.emit(player.player_id, draw_count)


func execute_start_phase_discard(state: GameState) -> void:
	var player := state.get_current_player()

	# Clear strategy cards placed before this turn
	# Collect indices to discard first, then process (replacement effects handled by helper)
	var indices_to_discard: Array[int] = []
	for i in range(player.strategy_zones.size()):
		if not player.strategy_zones[i].is_empty():
			if player.strategy_zone_turn_placed[i] < state.turn_number:
				# Base strategies are exempt from start phase discard (12.9.2 / 7.2.3)
				if effect_handler and effect_handler.is_base_strategy(player.strategy_zones[i]):
					continue
				# Cards with custom anti-discard rule text (e.g. EBP04-089) are also exempt
				if effect_handler and effect_handler.prevents_self_start_phase_discard(player.player_id, player.strategy_zones[i]):
					continue
				indices_to_discard.append(i)

	if not indices_to_discard.is_empty():
		var cleared: Array = []
		for i in indices_to_discard:
			if effect_handler:
				# Start phase discard (7.2.3) is a rule action, not <Destroy> — bypass protection.
				var card := await effect_handler.discard_strategy_from_zone(player.player_id, i, null, true)
				if not card.is_empty():
					cleared.append(card)
			else:
				var strategy_card: Dictionary = player.strategy_zones[i]
				player.strategy_zones[i] = {}
				player.discard_pile.append(strategy_card)
				cleared.append(strategy_card)
		if not effect_handler and not cleared.is_empty():
			player.strategy_zones_changed.emit()
			player.discard_changed.emit()
		if not cleared.is_empty():
			strategy_cleared.emit(player.player_id, cleared)


func execute_start_phase_reset(state: GameState) -> void:
	var player := state.get_current_player()

	# Reset rage to 0, allowing effects to intercept (e.g. EBP04-010)
	var old_rage: int = player.rage
	var new_rage: int = 0
	if effect_handler:
		new_rage = await effect_handler.apply_rage_reset(player.player_id)
	player.rage = new_rage
	player.rage_changed.emit(new_rage)
	# Fire rage_changed trigger so cards that watch for rage decrease (EBP04-089)
	# pick up the start phase reset. Populate the claim bucket on decrease so
	# they can pop markers as a true resource; clear leftovers afterwards.
	if effect_handler and new_rage != old_rage:
		var delta: int = old_rage - new_rage
		if delta > 0:
			player.push_pending_rage_markers(delta)
		await effect_handler.trigger_rage_changed(player.player_id, old_rage, new_rage)
		if delta > 0:
			player.pending_rage_markers.clear()

	# Reset per-turn flags
	player.has_invaded_this_turn = false
	player.has_played_monster_this_turn = false
	player.invasion_zones_crossed = 0

	# Clear destroyed-this-turn tracking for both players
	for p in state.players:
		p.cards_destroyed_this_turn.clear()


func execute_end_phase_burst_discard(state: GameState) -> void:
	## Discard Burst monster at beginning of end phase and restore previous monster.
	var player := state.get_current_player()
	if not player.burst_monster.is_empty():
		var burst_card: Dictionary = player.burst_monster
		player.discard_pile.append(burst_card)
		player.current_monster = player.pre_burst_monster
		# Pop the pre-burst monster off the stack (it was pushed when burst was played)
		if not player.monster_stack.is_empty():
			player.monster_stack.pop_front()
		player.burst_monster = {}
		player.pre_burst_monster = {}
		player.monster_changed.emit()
		player.discard_changed.emit()
		if effect_handler:
			await effect_handler.trigger_burst_discard(player.player_id, burst_card)


func execute_end_phase_advance(state: GameState) -> void:
	## Advance monster (7.5.2) and check crush rule.
	## Extra advance from effects (e.g. EBP02-056 SpaceGodzilla R4) adds additional zones.
	## Movement fully resolves before triggered abilities activate; cards crushed during
	## movement are filtered out of the standby queue.
	var player := state.get_current_player()

	# Check if monster is blocked from advancing (e.g. Biollante Rose Form)
	if effect_handler and effect_handler.is_monster_advance_blocked(player.player_id):
		return

	var extra: int = 0
	if effect_handler:
		extra = effect_handler.get_extra_end_phase_advance(player.player_id)
	var total_advance: int = 1 + extra
	var deferred_entries: Array = []
	for _step in range(total_advance):
		if player.monster_zone > 7:
			break
		var old_zone: int = player.monster_zone
		player.monster_zone += 1
		monster_advanced.emit(player.player_id, old_zone, player.monster_zone)
		player.monster_changed.emit()
		if effect_handler:
			deferred_entries.append_array(effect_handler.collect_monster_advance_entries(player.player_id, old_zone, player.monster_zone))
		await check_crush_rule(state, deferred_entries)

	# Resolve deferred effects after all movement completes
	if effect_handler and not deferred_entries.is_empty():
		await effect_handler.resolve_deferred_entries(deferred_entries)


func execute_end_phase_draw(state: GameState) -> void:
	## Draw up to 5 cards (7.5.4).
	var player := state.get_current_player()
	# Skip silently if hand is already at the cap — no draw would happen anyway,
	# so the "draw blocked" log line would just be noise.
	if player.hand.size() >= 5:
		return
	if effect_handler and effect_handler.is_opponent_end_phase_draw_blocked(player.player_id):
		effect_handler.log_message.emit(tr("STR_AH_END_PHASE_DRAW_BLOCKED"))
		return
	var drawn := player.draw_up_to(5)
	if drawn.size() > 0:
		cards_drawn.emit(player.player_id, drawn.size())


func resolve_counter(state: GameState) -> void:
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()
	var total_cp: int = player.get_total_counter_power()
	var threat: int = opponent.get_threat_level()
	# Apply effect modifiers
	if effect_handler:
		total_cp += effect_handler.get_counter_power_modifier(player.player_id)
		threat += effect_handler.get_threat_level_modifier(opponent.player_id)
		# Subtract base CP of cards restricted from engaging by opponent's monster
		total_cp -= effect_handler.get_engagement_restricted_cp(player.player_id)

	# Full counter prevention (e.g. EBP04-014/031/032): no retreat, no rank up —
	# counter simply doesn't happen. Distinct from counter immunity which still
	# retreats. Prevention may be CP-conditional, hence the total_cp parameter.
	if effect_handler and effect_handler.is_counter_prevented(opponent.player_id, total_cp):
		counter_prevented.emit(opponent.player_id)
		return

	# Check counter immunity (e.g. EBP02-027: CP <= threshold → retreat without rank up)
	var immunity_threshold: int = 0
	if effect_handler:
		immunity_threshold = effect_handler.get_counter_immunity_threshold(opponent.player_id)

	if immunity_threshold > 0 and total_cp <= immunity_threshold:
		# Counter is immune — monster retreats but does NOT rank up
		counter_immunity_triggered.emit(player.player_id, total_cp, immunity_threshold)

		var retreat_zone: int = get_counter_retreat_zone(opponent.monster_zone)
		if retreat_zone != opponent.monster_zone:
			var old_zone: int = opponent.monster_zone
			opponent.monster_zone = retreat_zone
			monster_advanced.emit(opponent.player_id, old_zone, opponent.monster_zone)
			opponent.monster_changed.emit()
	elif total_cp >= threat:
		counter_succeeded.emit(player.player_id, total_cp, threat)

		# Counter retreat: only zones 6-8 move back (5.15.1.1)
		var retreat_zone: int = get_counter_retreat_zone(opponent.monster_zone)
		if retreat_zone != opponent.monster_zone:
			var old_zone: int = opponent.monster_zone
			opponent.monster_zone = retreat_zone
			monster_advanced.emit(opponent.player_id, old_zone, opponent.monster_zone)
			opponent.monster_changed.emit()

		# Trigger counter success effects after retreat but before rank-up.
		# Counterer (player, current player) handles on_counter_success;
		# countered monster (opponent) handles on_self_countered.
		if effect_handler:
			await effect_handler.trigger_counter_success(player.player_id, opponent.player_id)

		# Opponent must rank up their monster
		await _rank_up_monster(state, opponent, player.player_id)
	else:
		counter_failed.emit(player.player_id, total_cp, threat)


func force_counter(state: GameState, target_player_id: int) -> void:
	## Force a successful counter against target_player_id's monster.
	## The target's monster retreats and ranks up (or target loses if can't rank up).
	## The non-target player is recorded as the counter winner.
	## Used by EBP02-012 (counter opponent's monster) and EBP04-027 (counter Gigan itself).
	var winner_id: int = 1 - target_player_id
	var target := state.players[target_player_id]

	# Counter retreat: only zones 6-8 move back (5.15.1.1)
	var retreat_zone: int = get_counter_retreat_zone(target.monster_zone)
	if retreat_zone != target.monster_zone:
		var old_zone: int = target.monster_zone
		target.monster_zone = retreat_zone
		monster_advanced.emit(target_player_id, old_zone, target.monster_zone)
		target.monster_changed.emit()

	# Target must rank up their monster
	await _rank_up_monster(state, target, winner_id)


func _rank_up_monster(state: GameState, opponent: PlayerState, winner_player_id: int) -> void:
	## Prompt the opponent to choose a rank-up monster from their monster deck.
	## If the monster deck is empty or has no valid targets, opponent loses immediately.
	if opponent.monster_deck.is_empty():
		state.game_over.emit(winner_player_id, "STR_LOG_REASON_COUNTER_VICTORY")
		return

	var next_rank: int = opponent.current_monster.get("rank", 1) + 1
	var cur_traits: Array = opponent.current_monster.get("traits", [])

	# Build valid indices (monsters that match rank + trait requirements).
	# Also accept monsters whose can_play_as_monster() alternate bridge is satisfied
	# (e.g. EBP04-033/034 "play on top of Monster X" — their [Kaiser Ghidorah] trait
	# does not overlap [Monster X] but rank-up is still permitted by the alternate cost).
	var valid_indices: Array[int] = []
	for i in range(opponent.monster_deck.size()):
		var m: Dictionary = opponent.monster_deck[i]
		if m.get("rank") != next_rank:
			continue
		var trait_ok := _traits_overlap(m.get("traits", []), cur_traits)
		if not trait_ok and effect_handler:
			trait_ok = effect_handler.can_play_as_monster(opponent.player_id, m)
		if trait_ok:
			valid_indices.append(i)

	if valid_indices.is_empty():
		# No valid rank-up targets — opponent loses
		state.game_over.emit(winner_player_id, "STR_LOG_REASON_COUNTER_VICTORY")
		return

	# Request player selection via UI
	var prompt := tr("STR_AH_CHOOSE_RANKUP_FMT") % next_rank

	var chosen_index: int = -1
	if monster_rankup_requested.get_connections().size() > 0:
		var monsters: Array[Dictionary] = []
		monsters.assign(opponent.monster_deck)
		monster_rankup_requested.emit(opponent.player_id, monsters, valid_indices, prompt)
		await _monster_rankup_resolved
		chosen_index = _monster_rankup_result
	else:
		# Fallback: auto-pick first valid
		chosen_index = valid_indices[0]

	if chosen_index >= 0 and chosen_index < opponent.monster_deck.size():
		var m: Dictionary = opponent.monster_deck[chosen_index]
		var old_monster: Dictionary = opponent.current_monster
		if not old_monster.is_empty():
			opponent.monster_stack.push_front(old_monster)
		opponent.current_monster = m
		opponent.monster_deck.erase(m)
		opponent.rage = 0
		opponent.rage_changed.emit(0)
		monster_countered.emit(opponent.player_id, old_monster, m)
		opponent.monster_changed.emit()
		if effect_handler:
			await effect_handler.trigger_enter(opponent.player_id, m, true)
	else:
		# Opponent loses - can't find valid rank-up monster
		state.game_over.emit(winner_player_id, "STR_LOG_REASON_COUNTER_VICTORY")


func resolve_monster_rankup(index: int) -> void:
	## Called by the presentation layer after the player selects a rank-up monster.
	_monster_rankup_result = index
	_monster_rankup_resolved.emit()


func play_monster_from_effect(state: GameState, player_id: int, monster_card: Dictionary) -> void:
	## Play a monster card from the monster deck without rage increase.
	## Used by strategy effects like EBP03-074 (A Journey of 130 Million Years).
	var player := state.players[player_id]
	var old_monster: Dictionary = player.current_monster

	# Push old monster onto the stack
	if not old_monster.is_empty():
		player.monster_stack.push_front(old_monster)

	# If a burst monster is active, the new monster buries it in the stack.
	# Clear burst state so the burst card isn't discarded at end of turn.
	if not player.burst_monster.is_empty():
		player.burst_monster = {}
		player.pre_burst_monster = {}

	player.has_played_monster_this_turn = true
	player.current_monster = monster_card
	player.monster_deck.erase(monster_card)
	monster_played.emit(player_id, old_monster, monster_card)
	player.monster_changed.emit()
	if effect_handler:
		await effect_handler.trigger_enter(player_id, monster_card, true)
		await effect_handler.trigger_monster_played(player_id, old_monster, monster_card)


func resolve_check_timing(state: GameState) -> void:
	## Resolve all rule actions at a check timing (10.4.3, 11.1.2).
	## Per 11.1.2.1: interrupt rule actions (crush) resolve first.
	## Per 10.4.3.1: repeat until no more rule actions remain.
	var changed := true
	while changed:
		changed = false
		# Interrupt rule actions first (11.1.2.1): crush rule (11.3)
		if await _check_crush_for_player(state, state.current_player_id):
			changed = true
		if await _check_crush_for_player(state, 1 - state.current_player_id):
			changed = true
		# Non-interrupt rule actions
		for pid in range(2):
			if _resolve_illegal_cards(state.players[pid]):
				changed = true
			if _resolve_overloaded_cards(state.players[pid]):
				changed = true


func check_crush_rule(state: GameState, deferred_entries: Variant = null) -> void:
	## Interrupt type rule action (11.3): destroy battle cards sharing a zone with a monster.
	## Per 11.1.2.1.1: turn player's interrupt rule actions resolve first.
	## When deferred_entries is provided, crush/revenge effects are collected for later
	## standby resolution instead of triggering immediately (used during movement).
	await _check_crush_for_player(state, state.current_player_id, deferred_entries)
	await _check_crush_for_player(state, 1 - state.current_player_id, deferred_entries)


func _check_crush_for_player(state: GameState, player_id: int, deferred_entries: Variant = null) -> bool:
	## Check if this player's monster shares a zone with a battle card. Returns true if crushed.
	## When deferred_entries is provided, crush/revenge effects are collected instead of
	## triggering immediately, so movement can fully resolve first.
	var player := state.players[player_id]

	# Monsters and battle cards occupy the SAME player's zones.
	# The crush rule (11.3): if a battle card is in the same zone as the monster, destroy it.
	var monster_zone_idx: int = player.monster_zone - 1  # 0-indexed
	if monster_zone_idx >= 0 and monster_zone_idx < 8:
		if player.zone_has_cards(monster_zone_idx):
			var crushed_stack: Array = player.clear_zone(monster_zone_idx)
			EffectHandler.banish_or_discard(player, crushed_stack)
			player.cards_destroyed_this_turn.append(crushed_stack[0])
			battle_card_crushed.emit(player_id, monster_zone_idx, crushed_stack[0])
			player.zones_changed.emit()
			player.discard_changed.emit()
			if effect_handler:
				if deferred_entries != null:
					deferred_entries.append_array(effect_handler.collect_crush_and_revenge_entries(player_id, crushed_stack[0]))
				else:
					await effect_handler.trigger_crush(player_id, crushed_stack[0])
					await effect_handler.trigger_revenge(player_id, crushed_stack[0])
			return true
	return false


func _resolve_illegal_cards(player: PlayerState) -> bool:
	## Rule 11.4 - Illegal Cards (non-interrupt rule action).
	## Strategy cards in zones that are not stacked under a battle/monster card → discard.
	## Non-strategy cards in strategy zones → discard.
	var changed := false

	# Check zones: strategy cards not stacked under another card are illegal
	for i in range(8):
		if player.is_zone_empty(i):
			continue
		var top_card := player.get_zone_top_card(i)
		if top_card.get("card_type") == CardEnums.CardType.STRATEGY:
			var stack: Array = player.clear_zone(i)
			EffectHandler.banish_or_discard(player, stack)
			changed = true

	# Check strategy zones: non-strategy cards are illegal
	for i in range(2):
		if player.strategy_zones[i].is_empty():
			continue
		if player.strategy_zones[i].get("card_type") != CardEnums.CardType.STRATEGY:
			EffectHandler.banish_or_discard(player, [player.strategy_zones[i]])
			player.strategy_zones[i] = {}
			changed = true

	if changed:
		player.zones_changed.emit()
		player.strategy_zones_changed.emit()
		player.discard_changed.emit()
	return changed


func _resolve_overloaded_cards(player: PlayerState) -> bool:
	## Rule 11.5 - Overloaded Cards (non-interrupt rule action).
	## If any zone has multiple battle cards not in a stack, or any strategy zone has
	## multiple strategy cards, keep the last placed and destroy the rest.
	## In practice: our zones use stacks (single Array per zone) and strategy zones hold
	## single cards, so this can only occur if a card effect places cards irregularly.
	## Currently a no-op safety check for future expansion.
	return false


static func get_retreat_zone(current_zone: int) -> int:
	## Retreat: move back by 1 zone (5.13.2). Zone 1 stays in zone 1 (5.13.2.1).
	return maxi(current_zone - 1, 1)


static func get_counter_retreat_zone(current_zone: int) -> int:
	## Get the zone a monster moves to when countered (5.15.1.1).
	## Only zones 6, 7, 8 move — to the zone behind (4.4.5.1).
	## Zones 1-5 do not move when countered.
	match current_zone:
		6: return 5
		7: return 4
		8: return 3
	return current_zone


func _traits_overlap(traits_a: Array, traits_b: Array) -> bool:
	for t in traits_a:
		if t in traits_b:
			return true
	return false


# --- Private action implementations ---

func _play_battle_card(hand_index: int, zone_index: int, state: GameState) -> void:
	var player := state.get_current_player()

	var card: Dictionary = player.hand.pop_at(hand_index)

	# Apply optional play costs (e.g., ESC01-001 discard a Godzilla card for rank reduction)
	if effect_handler:
		var proceed: bool = await effect_handler.apply_play_cost(player.player_id, card, zone_index)
		if not proceed:
			# Cost declined — restore card to hand and force visual rebuild
			player.hand.insert(mini(hand_index, player.hand.size()), card)
			player.hand_changed.emit()
			play_cancelled.emit(player.player_id)
			return

	# Rule 11.5 - Overloaded Cards: if zone is occupied, destroy existing cards
	# Unless the card's effect says to stack on top (e.g. Godzilla Jr. on Little Godzilla)
	if player.zone_has_cards(zone_index):
		var should_stack := false
		if effect_handler:
			should_stack = effect_handler.should_stack_on_play(player.player_id, card, zone_index)
		if not should_stack:
			var destroyed_stack: Array = player.clear_zone(zone_index)
			EffectHandler.banish_or_discard(player, destroyed_stack)
			player.discard_changed.emit()

	player.push_zone_card(zone_index, card)
	battle_card_played.emit(player.player_id, card, zone_index)
	player.hand_changed.emit()
	player.zones_changed.emit()
	if effect_handler:
		# Log the action before triggered effects fire so the log reads in causal order
		var has_enter := effect_handler.has_trigger(card, "on_enter")
		effect_handler.log_message.emit(
			GameLog.played_battle(player.player_id, card.get("id", ""), zone_index, has_enter))
		await effect_handler.trigger_enter(player.player_id, card)
		await effect_handler.trigger_battle_card_played(player.player_id, card, zone_index)


func _play_strategy_card(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	var sz_index: int = player.get_first_empty_strategy_zone_index()
	player.strategy_zones[sz_index] = card
	player.strategy_zone_turn_placed[sz_index] = state.turn_number
	strategy_card_played.emit(player.player_id, card, sz_index)
	player.hand_changed.emit()
	player.strategy_zones_changed.emit()
	if effect_handler:
		effect_handler.log_message.emit(
			GameLog.played_strategy(player.player_id, card.get("id", ""), card.get("is_base", false)))
		await effect_handler.trigger_enter(player.player_id, card)


func _gain_rage(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	var old_rage: int = player.rage
	player.discard_pile.append(card)
	player.rage += 1
	card_discarded.emit(player.player_id, card)
	rage_gained.emit(player.player_id, player.rage)
	player.hand_changed.emit()
	player.rage_changed.emit(player.rage)
	player.discard_changed.emit()
	if effect_handler:
		effect_handler.log_message.emit(
			GameLog.gained_rage(player.player_id, player.rage, card.get("id", "")))
		await effect_handler.trigger_discard_from_hand(player.player_id, card)
		await effect_handler.trigger_hand_card_discarded(player.player_id, card)
		await effect_handler.trigger_rage_changed(player.player_id, old_rage, player.rage)


func _play_monster(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	var old_monster: Dictionary = player.current_monster
	var old_rage: int = player.rage

	# Alternate play cost (e.g. EBP04-012): execute cost before committing, allow cancel
	var rank_mismatch: bool = card.get("rank", 0) != old_monster.get("rank", 0)
	if rank_mismatch and effect_handler and effect_handler.has_trigger(card, "apply_play_cost"):
		var cost_ok: bool = await effect_handler.apply_play_cost(player.player_id, card, -1)
		if not cost_ok:
			# Cost declined — restore card to hand and force visual rebuild
			player.hand.insert(hand_index, card)
			player.hand_changed.emit()
			play_cancelled.emit(player.player_id)
			return
		rank_mismatch = false  # Not a burst play — cost was paid

	# Detect Burst play: card rank doesn't match current monster rank
	var is_burst_play: bool = rank_mismatch
	if is_burst_play:
		player.pre_burst_monster = old_monster
		player.burst_monster = card

	# Push old monster onto the stack (both normal and burst)
	if not old_monster.is_empty():
		player.monster_stack.push_front(old_monster)

	player.has_played_monster_this_turn = true

	player.current_monster = card
	player.rage += 1
	monster_played.emit(player.player_id, old_monster, card)
	rage_gained.emit(player.player_id, player.rage)
	player.hand_changed.emit()
	player.monster_changed.emit()
	player.rage_changed.emit(player.rage)
	if effect_handler:
		if is_burst_play:
			var burst_effect := effect_handler.get_effect(card)
			var burst_rank: int = burst_effect.get_burst_rank() if burst_effect else -1
			effect_handler.log_message.emit(
				GameLog.burst_played(player.player_id, card.get("id", ""), burst_rank, player.rage))
		else:
			effect_handler.log_message.emit(
				GameLog.played_monster(player.player_id, card.get("id", ""), player.rage))
		await effect_handler.trigger_enter(player.player_id, card)
		await effect_handler.trigger_monster_played(player.player_id, old_monster, card)
		await effect_handler.trigger_rage_changed(player.player_id, old_rage, player.rage)


func _invade(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	var advance_amount: int = card.get("invasion_icon", 0)
	player.has_invaded_this_turn = true
	player.last_invasion_card = card
	var start_zone: int = player.monster_zone

	# Check if invade1 cost is blocked by opponent (e.g. EBP04-029 Gigan R3)
	if advance_amount == 1 and effect_handler and effect_handler.is_invade1_cost_blocked(player.player_id):
		# Card stays in hand — return it and abort invasion. Emit play_cancelled
		# so the UI restores the dragged card's hand position (matches the
		# monster-cost-cancelled flow in _play_monster).
		player.hand.insert(hand_index, card)
		player.has_invaded_this_turn = false
		effect_handler.log_message.emit(tr("STR_AH_INVADE1_BLOCKED"))
		play_cancelled.emit(player.player_id)
		return

	# Check for invasion cost replacement (e.g. EBP03-004: mill from deck instead)
	var replaced_cost := false
	if effect_handler and effect_handler.can_replace_invasion_cost(player.player_id):
		var choice: int = await effect_handler.select_choice(
			player.player_id,
			[tr("STR_AH_INVADE_COST_MILL"), tr("STR_AH_INVADE_COST_HAND")] as Array[String],
			tr("STR_AH_INVADE_COST_PROMPT")
		)
		if choice == 0 and not player.main_deck.is_empty():
			# Mill from deck; return invasion card to hand
			player.hand.insert(hand_index, card)
			player.mill_cards(1)
			replaced_cost = true

	if not replaced_cost:
		player.discard_pile.append(card)
		card_discarded.emit(player.player_id, card)
		player.hand_changed.emit()
		player.discard_changed.emit()

	# Log the invade action right after the cost is paid, before movement and triggered
	# effects fire, so the log reads in causal order (action announced first, then effects).
	if effect_handler:
		effect_handler.log_message.emit(GameLog.invaded(
			player.player_id, card.get("id", ""),
			card.get("invasion_icon", 0) >= 2))

	# Apply per-monster invasion advance bonuses (e.g. EBP04-007 Godzilla 1962: +1 on Invade 1).
	if effect_handler:
		advance_amount += effect_handler.get_invasion_advance_bonus(player.player_id, card.get("invasion_icon", 0))

	# Advance step by step, collecting effect entries for deferred resolution.
	# Movement fully resolves before triggered abilities activate; cards removed
	# during movement (crush) are filtered from the queue. Base strategy destruction
	# is deferred to after movement but before standby resolution (12.9.2).
	var deferred_entries: Array = []

	# Collect discard triggers for deferred resolution alongside movement effects
	if not replaced_cost and effect_handler:
		deferred_entries.append_array(effect_handler.collect_discarded_for_invasion_entries(player.player_id, card))
		deferred_entries.append_array(effect_handler.collect_discard_from_hand_entries(player.player_id, card))
		deferred_entries.append_array(effect_handler.collect_hand_card_discarded_entries(player.player_id, card))
	var is_victory := false
	for _step in range(advance_amount):
		if player.monster_zone >= 8:
			# Check invasion victory
			var opponent := state.get_opponent_of_current()
			if not opponent.zone_has_battle_card(7):  # Zone 8 = index 7
				var old_zone: int = player.monster_zone
				player.monster_zone = 9  # Past zone 8
				monster_advanced.emit(player.player_id, old_zone, player.monster_zone)
				player.monster_changed.emit()
				if effect_handler:
					deferred_entries.append_array(effect_handler.collect_when_invading_entries(player.player_id, old_zone, player.monster_zone))
				is_victory = true
				break
			else:
				# Opponent's zone 8 has a battle card, can't advance further
				break
		else:
			var old_zone: int = player.monster_zone
			player.monster_zone += 1
			monster_advanced.emit(player.player_id, old_zone, player.monster_zone)
			if effect_handler:
				deferred_entries.append_array(effect_handler.collect_when_invading_entries(player.player_id, old_zone, player.monster_zone))
				deferred_entries.append_array(effect_handler.collect_monster_advance_entries(player.player_id, old_zone, player.monster_zone))
			# Check crush rule at each step (effects deferred until after movement)
			await check_crush_rule(state, deferred_entries)

	player.invasion_zones_crossed = player.monster_zone - start_zone

	if is_victory:
		state.game_over.emit(player.player_id, "STR_LOG_REASON_INVASION_VICTORY")
		return

	# Destroy <Base> strategies after movement completes but before standby (12.9.2).
	# The physical destruction happens now; strategy_discarded triggers join deferred_entries.
	if effect_handler and player.monster_zone >= 6:
		await effect_handler.destroy_base_strategies_on_invasion(player.monster_zone, deferred_entries)

	# Collect invasion observed entries once for the entire invasion
	if effect_handler and player.monster_zone > start_zone:
		deferred_entries.append_array(effect_handler.collect_invasion_observed_entries(player.player_id, start_zone, player.monster_zone))

	# Resolve deferred effects after all movement and rule actions complete
	if effect_handler and not deferred_entries.is_empty():
		await effect_handler.resolve_deferred_entries(deferred_entries)

	player.hand_changed.emit()
	player.monster_changed.emit()
	player.discard_changed.emit()
