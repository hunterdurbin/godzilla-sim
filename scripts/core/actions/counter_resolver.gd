class_name CounterResolver
extends ActionResolver

## Counter-phase resolution (rule 5.15): CP-vs-threat computation, the four
## outcome branches (prevention / immunity / success / failure), retreat
## zones, and the rank-up flow (including loss when no rank-up exists).


## Pure computation of the counter numbers — the most unit-testable piece of
## the counter phase. Returns {total_cp, threat, rage_threat, effect_threat,
## immunity_threshold, prevented}.
func compute_counter_numbers(state: GameState) -> Dictionary:
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()
	var total_cp: int = player.get_total_counter_power()
	var threat: int = opponent.get_threat_level()
	# Threat breakdown for the log (base printed threat + rage + effect modifiers).
	# rage_threat is the universal +5000-per-Rage term every monster carries.
	var rage_threat: int = opponent.rage * 5000
	var effect_threat: int = 0
	var immunity_threshold: int = 0
	var prevented := false
	# Apply effect modifiers
	if effect_handler:
		total_cp += effect_handler.get_counter_power_modifier(player.player_id)
		effect_threat = effect_handler.get_threat_level_modifier(opponent.player_id)
		threat += effect_threat
		# Subtract base CP of cards restricted from engaging by opponent's monster
		total_cp -= effect_handler.get_engagement_restricted_cp(player.player_id)
		immunity_threshold = effect_handler.get_counter_immunity_threshold(opponent.player_id)
		# Full counter prevention (e.g. EBP04-014/031/032): no retreat, no rank
		# up — counter simply doesn't happen. Distinct from counter immunity
		# which still retreats. May be CP-conditional, hence total_cp.
		prevented = effect_handler.is_counter_prevented(opponent.player_id, total_cp)
	return {
		"total_cp": total_cp,
		"threat": threat,
		"rage_threat": rage_threat,
		"effect_threat": effect_threat,
		"immunity_threshold": immunity_threshold,
		"prevented": prevented,
	}


func resolve_counter(state: GameState) -> void:
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()
	var numbers := compute_counter_numbers(state)
	var total_cp: int = numbers["total_cp"]
	var threat: int = numbers["threat"]

	if numbers["prevented"]:
		events.counter_prevented.emit(opponent.player_id)
		return

	# Counter immunity (e.g. EBP02-027: CP between threat and threshold →
	# retreat without rank up). Per rule wording the opponent must still have
	# enough counter power to "pseudo-counter" — if CP < threat the counter
	# just fails normally.
	var immunity_threshold: int = numbers["immunity_threshold"]
	if immunity_threshold > 0 and total_cp >= threat and total_cp <= immunity_threshold:
		# Counter is immune — monster retreats but does NOT rank up
		events.counter_immunity_triggered.emit(player.player_id, total_cp, immunity_threshold)
		_apply_counter_retreat(opponent)
	elif total_cp >= threat:
		events.counter_succeeded.emit(player.player_id, total_cp, threat, numbers["rage_threat"], numbers["effect_threat"])
		_apply_counter_retreat(opponent)

		# Counter success abilities enter standby after the retreat: counterer
		# (player, current player) on_counter_success, countered monster
		# (opponent) on_self_countered. They resolve at the 7.4.4 check timing
		# in one pool with the new monster's <Enter>. Q513: "The player who
		# controls that monster card chooses the order of resolution." If the
		# rank-up is impossible the game ends first (5.15.1.2.1).
		if effect_handler:
			effect_handler.trigger_counter_success(player.player_id, opponent.player_id)

		# Opponent must rank up their monster
		await _rank_up_monster(state, opponent, player.player_id)
	else:
		events.counter_failed.emit(player.player_id, total_cp, threat, numbers["rage_threat"], numbers["effect_threat"])


func force_counter(state: GameState, target_player_id: int) -> void:
	## Force a successful counter against target_player_id's monster.
	## The target's monster retreats and ranks up (or target loses if can't rank up).
	## The non-target player is recorded as the counter winner.
	## Used by EBP02-012 (counter opponent's monster) and EBP04-027 (counter Gigan itself).
	var winner_id: int = 1 - target_player_id
	var target := state.players[target_player_id]
	_apply_counter_retreat(target)
	# Target must rank up their monster
	await _rank_up_monster(state, target, winner_id)


func _apply_counter_retreat(target: PlayerState) -> void:
	## Counter retreat (5.15.1.1) through the monster movement module. A
	## battle card in the retreat zone is crushed right away — crush is an
	## interrupt rule action (11.1.2.1, 11.3) — so the crushed card's
	## abilities go to standby before the counter-success triggers and the
	## new monster's <Enter>. A rule action: no move blocking applies.
	effect_handler.monster_mover.counter_retreat(target.player_id)


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
	# (e.g. EBP04-033/034 "play on top of Monster X" — their [Kaizer Ghidorah] trait
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

	# Request player selection via the input layer (UI/RPC/bot or test script)
	var prompt := tr("STR_AH_CHOOSE_RANKUP_FMT") % next_rank
	var monsters: Array[Dictionary] = []
	monsters.assign(opponent.monster_deck)
	# Not redundant: SignalPlayerInput's override is a coroutine.
	@warning_ignore("redundant_await")
	var chosen_index: int = await input.choose_rankup(opponent.player_id, monsters, valid_indices, prompt)

	if chosen_index >= 0 and chosen_index < opponent.monster_deck.size():
		var m: Dictionary = opponent.monster_deck[chosen_index]
		var old_monster: Dictionary = opponent.current_monster
		if not old_monster.is_empty():
			opponent.monster_stack.push_front(old_monster)
		opponent.current_monster = m
		opponent.monster_deck.erase(m)
		# Rage carries over on counter rank-up — the start-phase reset on the
		# countered player's next turn handles the decrease (and lets watchers
		# like EBP04-089, which gate to "<Your Turn>", claim the markers).
		events.monster_countered.emit(opponent.player_id, old_monster, m)
		opponent.monster_changed.emit()
		if effect_handler:
			effect_handler.trigger_enter(opponent.player_id, m, true)
	else:
		# Opponent loses - can't find valid rank-up monster
		state.game_over.emit(winner_player_id, "STR_LOG_REASON_COUNTER_VICTORY")
