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

var effect_handler: EffectHandler


func execute(action: CardEnums.ActionType, params: Dictionary, state: GameState) -> void:
	match action:
		CardEnums.ActionType.PLAY_BATTLE:
			await _play_battle_card(params["hand_index"], params["zone_index"], state)
		CardEnums.ActionType.PLAY_STRATEGY:
			await _play_strategy_card(params["hand_index"], state)
		CardEnums.ActionType.GAIN_RAGE:
			_gain_rage(params["hand_index"], state)
		CardEnums.ActionType.PLAY_MONSTER:
			await _play_monster(params["hand_index"], state)
		CardEnums.ActionType.INVADE:
			await _invade(params["hand_index"], state)


func execute_start_phase(state: GameState) -> void:
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()

	# Draw cards equal to opponent's monster rank
	var draw_count: int = opponent.get_monster_rank()
	player.draw_cards(draw_count)
	cards_drawn.emit(player.player_id, draw_count)

	# Clear strategy cards placed before this turn
	var cleared: Array = []
	for i in range(2):
		if not player.strategy_zones[i].is_empty():
			if player.strategy_zone_turn_placed[i] < state.turn_number:
				cleared.append(player.strategy_zones[i])
				player.discard_pile.append(player.strategy_zones[i])
				player.strategy_zones[i] = {}
	if cleared.size() > 0:
		strategy_cleared.emit(player.player_id, cleared)
		player.strategy_zones_changed.emit()
		player.discard_changed.emit()

	# Reset rage to 0
	player.rage = 0
	player.rage_changed.emit(0)

	# Reset per-turn flags
	player.has_invaded_this_turn = false
	player.has_played_monster_this_turn = false


func execute_end_phase(state: GameState) -> void:
	var player := state.get_current_player()

	# Discard Burst monster at beginning of end phase and restore previous monster
	if not player.burst_monster.is_empty():
		var burst_card: Dictionary = player.burst_monster
		player.discard_pile.append(burst_card)
		player.current_monster = player.pre_burst_monster
		player.burst_monster = {}
		player.pre_burst_monster = {}
		player.monster_changed.emit()
		player.discard_changed.emit()

	# Advance monster if in zone <= 7
	if player.monster_zone <= 7:
		var old_zone: int = player.monster_zone
		player.monster_zone += 1
		monster_advanced.emit(player.player_id, old_zone, player.monster_zone)
		player.monster_changed.emit()
		if effect_handler:
			effect_handler.trigger_monster_advance(player.player_id, old_zone, player.monster_zone)

		# Check crush rule after advancing
		check_crush_rule(state)

	# Draw up to 5 cards
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

	if total_cp >= threat:
		counter_succeeded.emit(player.player_id, total_cp, threat)

		# Retreat monster to its retreat zone
		var retreat_zone: int = _get_retreat_zone(opponent.monster_zone)
		if retreat_zone != opponent.monster_zone:
			var old_zone: int = opponent.monster_zone
			opponent.monster_zone = retreat_zone
			monster_advanced.emit(opponent.player_id, old_zone, opponent.monster_zone)
			opponent.monster_changed.emit()

		# Opponent must rank up their monster
		var next_rank: int = opponent.current_monster.get("rank", 1) + 1
		var cur_trait = opponent.current_monster.get("trait")
		var found_next: bool = false

		for m in opponent.monster_deck:
			if m.get("rank") == next_rank and m.get("trait") == cur_trait:
				var old_monster: Dictionary = opponent.current_monster
				opponent.current_monster = m
				opponent.rage = 0
				opponent.rage_changed.emit(0)
				found_next = true
				monster_countered.emit(opponent.player_id, old_monster, m)
				opponent.monster_changed.emit()
				# Check crush rule after monster change (zone doesn't change here
				# but the monster is now different)
				break

		if not found_next:
			# Opponent loses - can't find valid rank-up monster
			state.game_over.emit(player.player_id, "Victory through countering!")
	else:
		counter_failed.emit(player.player_id, total_cp, threat)


func check_crush_rule(state: GameState) -> void:
	## If any invading monster shares a zone with a battle card, destroy that battle card
	for i in range(2):
		_check_crush_for_player(state, i)


func _check_crush_for_player(state: GameState, player_id: int) -> void:
	var player := state.players[player_id]
	var opponent := state.players[1 - player_id]

	# Check if opponent's monster is in a zone that has this player's battle card
	# The opponent's monster_zone is 1-8. We need to check if the zone (from this player's
	# perspective) is occupied. The zones are mirrored: opponent's zone 8 faces player's zone 8.
	# According to rules 4.4.5.4, zones in the same column:
	# player zone 3,8 <-> opponent zone 3,8
	# So when the opponent advances through zones 1-8, they're on THEIR side.
	# The crush rule (11.3) says: if a battle card is in the same zone as any invading monster.
	# A player's battle cards are in their own zones. The invading monster occupies a zone number.
	# The monster is conceptually on the field moving through zones.
	# For simplicity: the monster at zone N can crush battle cards at zone index N-1 of the
	# opponent (since the monster is invading towards the opponent).

	# Actually re-reading the rules: monsters and battle cards occupy the SAME player's zones.
	# The monster starts at zone 1 and advances towards zone 8, which are all the monster's
	# owner's zones. Battle cards are placed in the SAME player's zones to defend.
	# The crush rule: if a battle card is in the same zone as any invading monster, destroy it.
	# So we check if THIS player's monster is in a zone that has THIS player's battle card.
	var monster_zone_idx: int = player.monster_zone - 1  # 0-indexed
	if monster_zone_idx >= 0 and monster_zone_idx < 8:
		if not player.zones[monster_zone_idx].is_empty():
			var crushed: Dictionary = player.zones[monster_zone_idx]
			player.zones[monster_zone_idx] = {}
			player.discard_pile.append(crushed)
			battle_card_crushed.emit(player_id, monster_zone_idx, crushed)
			player.zones_changed.emit()
			player.discard_changed.emit()
			if effect_handler:
				effect_handler.trigger_crush(player_id, crushed)

	# Also check if the opponent's monster is in a zone with the opponent's battle card
	# (This is handled when we call this for both players)


func _get_retreat_zone(current_zone: int) -> int:
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


# --- Private action implementations ---

func _play_battle_card(hand_index: int, zone_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	player.zones[zone_index] = card
	battle_card_played.emit(player.player_id, card, zone_index)
	player.hand_changed.emit()
	player.zones_changed.emit()
	if effect_handler:
		await effect_handler.trigger_enter(player.player_id, card)


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
		effect_handler.trigger_rage_changed(player.player_id, old_rage, player.rage)


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
		effect_handler.trigger_monster_played(player.player_id, old_monster, card)
		effect_handler.trigger_rage_changed(player.player_id, old_rage, player.rage)


func _invade(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.hand.pop_at(hand_index)
	var advance_amount: int = card.get("invasion_icon", 0)
	player.discard_pile.append(card)
	player.has_invaded_this_turn = true

	card_discarded.emit(player.player_id, card)

	# Advance step by step (checking crush at each zone)
	for _step in range(advance_amount):
		if player.monster_zone >= 8:
			# Check invasion victory
			var opponent := state.get_opponent_of_current()
			if opponent.zones[7].is_empty():  # Zone 8 = index 7
				var old_zone: int = player.monster_zone
				player.monster_zone = 9  # Past zone 8
				monster_advanced.emit(player.player_id, old_zone, player.monster_zone)
				player.monster_changed.emit()
				if effect_handler:
					await effect_handler.trigger_when_invading(player.player_id, old_zone, player.monster_zone)
					effect_handler.trigger_monster_advance(player.player_id, old_zone, player.monster_zone)
				state.game_over.emit(player.player_id, "Victory through invasion!")
				return
			else:
				# Opponent's zone 8 has a battle card, can't advance further
				break
		else:
			var old_zone: int = player.monster_zone
			player.monster_zone += 1
			monster_advanced.emit(player.player_id, old_zone, player.monster_zone)
			if effect_handler:
				await effect_handler.trigger_when_invading(player.player_id, old_zone, player.monster_zone)
				effect_handler.trigger_monster_advance(player.player_id, old_zone, player.monster_zone)
			# Check crush rule at each step
			check_crush_rule(state)

	player.hand_changed.emit()
	player.monster_changed.emit()
	player.discard_changed.emit()
