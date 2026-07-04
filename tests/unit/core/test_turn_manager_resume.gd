extends GdUnitTestSuite

## TurnManager.resume_game(): re-entering the phase machine at a saved
## (phase, sub_phase) boundary. Boundary snapshots are captured at sub-phase
## entry, so resume must execute the saved sub-phase's step and everything
## after it — no skipped draws, no stale per-turn flags, no extra main phase.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func _resume_state(opts: Dictionary = {}) -> GameState:
	# Both players: vanilla monsters, decks of plain battle cards.
	var deck: Array = []
	for i in range(12):
		deck.append(Cards.battle(1, 5000, "DECK-%d" % i))
	var base := {
		"turn_number": 4,
		"p0": {"main_deck": deck.duplicate(true)},
		"p1": {"main_deck": deck.duplicate(true)},
	}
	for key in opts:
		if base.has(key) and base[key] is Dictionary:
			base[key].merge(opts[key], true)
		else:
			base[key] = opts[key]
	return States.make_state(base)


func test_resume_from_start_draw_boundary_draws_and_resets_flags() -> void:
	# Boundary captured at START sub 1 ("Draw Cards"), before the draw ran —
	# the per-turn flags still hold the previous turn's values.
	var state := _resume_state({"p0": {
		"rage": 3,
		"has_invaded_this_turn": true,
		"has_played_monster_this_turn": true,
	}})
	state.current_phase = CardEnums.GamePhase.START
	state.current_sub_phase = 1
	state.players[0].invasion_zones_crossed = 2
	state.players[0].cards_destroyed_this_turn.append(Cards.battle(1, 5000, "DEAD"))
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	var subs: Array = []
	tm.sub_phase_changed.connect(func(i: int) -> void: subs.append(i))

	tm.resume_game()

	# The draw ran (opponent monster rank 1).
	assert_int(state.players[0].hand.size()).is_equal(1)
	# The rage/flag reset ran.
	assert_int(state.players[0].rage).is_equal(0)
	assert_bool(state.players[0].has_invaded_this_turn).is_false()
	assert_bool(state.players[0].has_played_monster_this_turn).is_false()
	assert_int(state.players[0].invasion_zones_crossed).is_equal(0)
	assert_int(state.players[0].cards_destroyed_this_turn.size()).is_equal(0)
	# Same turn — resume must not bump the turn counter.
	assert_int(state.turn_number).is_equal(4)
	assert_int(state.current_phase).is_equal(CardEnums.GamePhase.MAIN)
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.AWAITING_ACTION)
	# START subs 1-3 ran (sub 0 phase-start effects were NOT re-run), then MAIN 0-1.
	assert_array(subs).contains_exactly([1, 2, 3, 0, 1])


func test_resume_from_main_actions_boundary_prompts_without_side_effects() -> void:
	var state := _resume_state({"p0": {"rage": 2, "hand": [Cards.battle(1, 5000, "H1")]}})
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_sub_phase = 1
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	var subs: Array = []
	tm.sub_phase_changed.connect(func(i: int) -> void: subs.append(i))

	tm.resume_game()

	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(state.players[0].rage).is_equal(2)
	assert_int(state.turn_number).is_equal(4)
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.AWAITING_ACTION)
	# Only the player-actions sub-phase re-entered; MAIN phase-start effects skipped.
	assert_array(subs).contains_exactly([1])


func test_resume_from_main_resolve_boundary_reruns_phase_start() -> void:
	# Snapshot at MAIN sub 0 entry predates the phase-start effects, so they run.
	var state := _resume_state()
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_sub_phase = 0
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	var subs: Array = []
	tm.sub_phase_changed.connect(func(i: int) -> void: subs.append(i))

	tm.resume_game()

	assert_array(subs).contains_exactly([0, 1])
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.AWAITING_ACTION)


func test_resume_from_counter_boundary_skips_extra_main_round() -> void:
	var state := _resume_state()
	state.current_phase = CardEnums.GamePhase.COUNTER
	state.current_sub_phase = 1
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	var counter_results: Array = []
	tm.events.counter_failed.connect(func(_pid: int, _cp: int, _t: int, _rt: int, _et: int) -> void:
		counter_results.append("failed"))
	var prompted_players: Array = []
	tm.awaiting_player_action.connect(func(_actions: Array) -> void:
		prompted_players.append(state.current_player_id))

	tm.resume_game()

	# Counter resolved once, then the turn finished and flipped — the saved
	# player never got a spurious extra main-phase action round.
	assert_array(counter_results).contains_exactly(["failed"])
	assert_array(prompted_players).contains_exactly([1])
	assert_int(state.players[0].monster_zone).is_equal(2)
	assert_int(state.players[0].hand.size()).is_equal(5)
	assert_int(state.turn_number).is_equal(5)
	assert_int(state.current_player_id).is_equal(1)
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.AWAITING_ACTION)


func test_resume_from_end_refill_boundary_does_not_readvance() -> void:
	# Boundary at END sub 2 ("Refill Hand") — the advance (sub 1) already
	# happened before the snapshot and must not run again.
	var state := _resume_state({"p0": {"monster_zone": 3}})
	state.current_phase = CardEnums.GamePhase.END
	state.current_sub_phase = 2
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())

	tm.resume_game()

	assert_int(state.players[0].monster_zone).is_equal(3)
	assert_int(state.players[0].hand.size()).is_equal(5)
	# The turn finished and the next one began for the other player.
	assert_int(state.turn_number).is_equal(5)
	assert_int(state.current_player_id).is_equal(1)
	assert_int(state.current_phase).is_equal(CardEnums.GamePhase.MAIN)
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.AWAITING_ACTION)
