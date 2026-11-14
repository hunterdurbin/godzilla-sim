class_name CounterResolver
extends ActionResolver

## Counter-phase resolution (rule 5.15): the four outcome branches
## (prevention / immunity / success / failure), retreat zones, and the
## rank-up flow (including loss when no rank-up exists).
## The rules themselves (counter numbers, rank-up eligibility) are
## RulesEngine's; this resolver applies their outcome.


func resolve_counter(state: GameState) -> void:
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()
	var numbers := rules_engine.compute_counter_numbers(state)
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
			dispatcher.trigger_counter_success(player.player_id, opponent.player_id)

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
	monster_mover.counter_retreat(target.player_id)


func _rank_up_monster(state: GameState, opponent: PlayerState, winner_player_id: int) -> void:
	## Prompt the opponent to choose a rank-up monster from their monster deck.
	## If the monster deck is empty or has no valid targets, opponent loses immediately.
	if opponent.monster_deck.is_empty():
		state.game_over.emit(winner_player_id, "STR_LOG_REASON_COUNTER_VICTORY")
		return

	var next_rank: int = opponent.current_monster.get("rank", 1) + 1
	var valid_indices := rules_engine.get_rank_up_candidates(opponent)

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
			dispatcher.trigger_enter(opponent.player_id, m, true)
	else:
		# Opponent loses - can't find valid rank-up monster
		state.game_over.emit(winner_player_id, "STR_LOG_REASON_COUNTER_VICTORY")
