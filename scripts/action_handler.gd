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

var effect_handler: EffectHandler


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
				indices_to_discard.append(i)

	if not indices_to_discard.is_empty():
		var cleared: Array = []
		for i in indices_to_discard:
			if effect_handler:
				var card := await effect_handler.discard_strategy_from_zone(player.player_id, i)
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

	# Reset rage to 0
	player.rage = 0
	player.rage_changed.emit(0)

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
		await check_crush_rule(state)

	# Resolve deferred effects after all movement completes
	if effect_handler and not deferred_entries.is_empty():
		await effect_handler.resolve_deferred_entries(deferred_entries)


func execute_end_phase_draw(state: GameState) -> void:
	## Draw up to 5 cards (7.5.4).
	var player := state.get_current_player()
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

	# Check counter immunity (e.g. EBP02-027: CP <= threshold → retreat without rank up)
	var immunity_threshold: int = 0
	if effect_handler:
		immunity_threshold = effect_handler.get_counter_immunity_threshold(opponent.player_id)

	if immunity_threshold > 0 and total_cp <= immunity_threshold:
		# Counter is immune — monster retreats but does NOT rank up
		counter_immunity_triggered.emit(player.player_id, total_cp, immunity_threshold)

		var retreat_zone: int = get_retreat_zone(opponent.monster_zone)
		if retreat_zone != opponent.monster_zone:
			var old_zone: int = opponent.monster_zone
			opponent.monster_zone = retreat_zone
			monster_advanced.emit(opponent.player_id, old_zone, opponent.monster_zone)
			opponent.monster_changed.emit()
	elif total_cp >= threat:
		counter_succeeded.emit(player.player_id, total_cp, threat)

		# Trigger counter success effects before retreat/rank-up
		if effect_handler:
			await effect_handler.trigger_counter_success(player.player_id)

		# Retreat monster to its retreat zone
		var retreat_zone: int = get_retreat_zone(opponent.monster_zone)
		if retreat_zone != opponent.monster_zone:
			var old_zone: int = opponent.monster_zone
			opponent.monster_zone = retreat_zone
			monster_advanced.emit(opponent.player_id, old_zone, opponent.monster_zone)
			opponent.monster_changed.emit()

		# Opponent must rank up their monster
		var next_rank: int = opponent.current_monster.get("rank", 1) + 1
		var cur_traits: Array = opponent.current_monster.get("traits", [])
		var found_next: bool = false

		for m in opponent.monster_deck:
			if m.get("rank") == next_rank and _traits_overlap(m.get("traits", []), cur_traits):
				var old_monster: Dictionary = opponent.current_monster
				if not old_monster.is_empty():
					opponent.monster_stack.push_front(old_monster)
				opponent.current_monster = m
				opponent.rage = 0
				opponent.rage_changed.emit(0)
				found_next = true
				monster_countered.emit(opponent.player_id, old_monster, m)
				opponent.monster_changed.emit()
				# Trigger enter effect on the new monster
				if effect_handler:
					await effect_handler.trigger_enter(opponent.player_id, m)
				break

		if not found_next:
			# Opponent loses - can't find valid rank-up monster
			state.game_over.emit(player.player_id, "Victory through countering!")
	else:
		counter_failed.emit(player.player_id, total_cp, threat)


func force_counter(state: GameState, counter_player_id: int) -> void:
	## Force a successful counter on the specified player's opponent's monster.
	## The opponent's monster retreats and ranks up (or opponent loses if can't rank up).
	## Used by EBP02-012 Godzilla(2016) Frozen.
	var opponent_id: int = 1 - counter_player_id
	var opponent := state.players[opponent_id]

	# Retreat monster to its retreat zone
	var retreat_zone: int = get_retreat_zone(opponent.monster_zone)
	if retreat_zone != opponent.monster_zone:
		var old_zone: int = opponent.monster_zone
		opponent.monster_zone = retreat_zone
		monster_advanced.emit(opponent_id, old_zone, opponent.monster_zone)
		opponent.monster_changed.emit()

	# Opponent must rank up their monster
	var next_rank: int = opponent.current_monster.get("rank", 1) + 1
	var cur_traits: Array = opponent.current_monster.get("traits", [])
	var found_next: bool = false

	for m in opponent.monster_deck:
		if m.get("rank") == next_rank and _traits_overlap(m.get("traits", []), cur_traits):
			var old_monster: Dictionary = opponent.current_monster
			if not old_monster.is_empty():
				opponent.monster_stack.push_front(old_monster)
			opponent.current_monster = m
			opponent.rage = 0
			opponent.rage_changed.emit(0)
			found_next = true
			monster_countered.emit(opponent_id, old_monster, m)
			opponent.monster_changed.emit()
			# Trigger enter effect on the new monster
			if effect_handler:
				await effect_handler.trigger_enter(opponent_id, m)
			break

	if not found_next:
		state.game_over.emit(counter_player_id, "Victory through countering!")


func play_monster_from_effect(state: GameState, player_id: int, monster_card: Dictionary) -> void:
	## Play a monster card from the monster deck without rage increase.
	## Used by strategy effects like EBP03-074 (A Journey of 130 Million Years).
	var player := state.players[player_id]
	var old_monster: Dictionary = player.current_monster

	# Push old monster onto the stack
	if not old_monster.is_empty():
		player.monster_stack.push_front(old_monster)

	player.current_monster = monster_card
	monster_played.emit(player_id, old_monster, monster_card)
	player.monster_changed.emit()
	if effect_handler:
		await effect_handler.trigger_enter(player_id, monster_card)
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


func check_crush_rule(state: GameState) -> void:
	## Interrupt type rule action (11.3): destroy battle cards sharing a zone with a monster.
	## Per 11.1.2.1.1: turn player's interrupt rule actions resolve first.
	await _check_crush_for_player(state, state.current_player_id)
	await _check_crush_for_player(state, 1 - state.current_player_id)


func _check_crush_for_player(state: GameState, player_id: int) -> bool:
	## Check if this player's monster shares a zone with a battle card. Returns true if crushed.
	var player := state.players[player_id]

	# Monsters and battle cards occupy the SAME player's zones.
	# The crush rule (11.3): if a battle card is in the same zone as the monster, destroy it.
	var monster_zone_idx: int = player.monster_zone - 1  # 0-indexed
	if monster_zone_idx >= 0 and monster_zone_idx < 8:
		if player.zone_has_cards(monster_zone_idx):
			var crushed_stack: Array = player.clear_zone(monster_zone_idx)
			EffectHandler.banish_or_discard(player, crushed_stack)
			battle_card_crushed.emit(player_id, monster_zone_idx, crushed_stack[0])
			player.zones_changed.emit()
			player.discard_changed.emit()
			if effect_handler:
				await effect_handler.trigger_crush(player_id, crushed_stack[0])
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
	## Get the zone a monster retreats to when countered.
	## Back row (1-5): retreat to previous back row zone.
	## Front row (6-8): retreat to same-column back row zone.
	match current_zone:
		1: return 1
		2: return 1
		3: return 2
		4: return 3
		5: return 4
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

	# Rule 11.5 - Overloaded Cards: if zone is occupied, destroy existing cards
	# Unless the card's effect says to stack on top (e.g. Godzilla Jr. on Little Godzilla)
	if player.zone_has_cards(zone_index):
		var should_stack := false
		if effect_handler:
			should_stack = effect_handler.should_stack_on_play(player.player_id, card, zone_index)
		if not should_stack:
			var destroyed_stack: Array = player.clear_zone(zone_index)
			var top_card: Dictionary = destroyed_stack[0]
			EffectHandler.banish_or_discard(player, destroyed_stack)
			player.discard_changed.emit()
			if effect_handler:
				await effect_handler.trigger_revenge(player.player_id, top_card)

	player.push_zone_card(zone_index, card)
	battle_card_played.emit(player.player_id, card, zone_index)
	player.hand_changed.emit()
	player.zones_changed.emit()
	if effect_handler:
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
		await effect_handler.trigger_discard_from_hand(player.player_id, card)
		await effect_handler.trigger_hand_card_discarded(player.player_id, card)
		await effect_handler.trigger_rage_changed(player.player_id, old_rage, player.rage)


func _play_monster(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	var old_monster: Dictionary = player.current_monster
	var old_rage: int = player.rage

	# Detect Burst play: card rank doesn't match current monster rank
	var is_burst_play: bool = card.get("rank", 0) != old_monster.get("rank", 0)
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

	# Check for invasion cost replacement (e.g. EBP03-004: mill from deck instead)
	var replaced_cost := false
	if effect_handler and effect_handler.can_replace_invasion_cost(player.player_id):
		var choice: int = await effect_handler.select_choice(
			player.player_id,
			["Send top deck card to discard", "Discard from hand"] as Array[String],
			"Choose invasion cost method:"
		)
		if choice == 0 and not player.main_deck.is_empty():
			# Mill from deck; return invasion card to hand
			player.hand.insert(hand_index, card)
			player.mill_cards(1)
			replaced_cost = true

	if not replaced_cost:
		player.discard_pile.append(card)
		card_discarded.emit(player.player_id, card)
		# Check if discarded card plays itself from discard (e.g. EBP03-061 Dagahra)
		if effect_handler:
			var discard_effect := effect_handler.get_effect(card)
			if discard_effect:
				var ctx := EffectContext.create(state, player.player_id, card, effect_handler)
				if discard_effect.on_discarded_for_invasion(ctx):
					await effect_handler.play_from_discard(player.player_id, card)

	# Advance step by step, collecting effect entries for deferred resolution.
	# Movement fully resolves before triggered abilities activate; cards removed
	# during movement (crush, base strategy destruction) are filtered from the queue.
	var deferred_entries: Array = []
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
				# Destroy <Base> strategies when monster invades into zones 6-8 (12.9.2)
				await effect_handler.destroy_base_strategies_on_invasion(player.monster_zone)
			# Check crush rule at each step
			await check_crush_rule(state)

	player.invasion_zones_crossed = player.monster_zone - start_zone

	# Collect invasion observed entries once for the entire invasion
	if effect_handler and player.monster_zone > start_zone:
		deferred_entries.append_array(effect_handler.collect_invasion_observed_entries(player.player_id, start_zone, player.monster_zone))

	# Resolve deferred effects after all movement completes
	if effect_handler and not deferred_entries.is_empty():
		await effect_handler.resolve_deferred_entries(deferred_entries)

	if is_victory:
		state.game_over.emit(player.player_id, "Victory through invasion!")
		return

	player.hand_changed.emit()
	player.monster_changed.emit()
	player.discard_changed.emit()
