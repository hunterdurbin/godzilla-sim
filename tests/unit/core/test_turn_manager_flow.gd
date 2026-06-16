extends GdUnitTestSuite

## TurnManager flow: full-turn progression with ScriptedPlayerInput,
## FlowState transitions, submit_action gating, and save/restore/resume.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func _flow_state(opts: Dictionary = {}) -> GameState:
	# Both players: vanilla monsters, decks of plain battle cards.
	var deck: Array = []
	for i in range(12):
		deck.append(Cards.battle(1, 5000, "DECK-%d" % i))
	var base := {
		"turn_number": 0,  # a fresh game pre-_begin_turn
		"p0": {"main_deck": deck.duplicate(true)},
		"p1": {"main_deck": deck.duplicate(true)},
	}
	for key in opts:
		if base.has(key) and base[key] is Dictionary:
			base[key].merge(opts[key], true)
		else:
			base[key] = opts[key]
	return States.make_state(base)


func test_start_game_runs_start_phase_into_main() -> void:
	var input := ScriptedPlayerInput.new()
	var state := _flow_state()
	var tm := States.make_turn_manager(state, input)
	var phases: Array = []
	tm.phase_started.connect(func(phase: CardEnums.GamePhase) -> void: phases.append(phase))

	tm.start_game(0)

	assert_int(state.turn_number).is_equal(1)
	assert_int(state.current_player_id).is_equal(0)
	assert_array(phases).contains_exactly([CardEnums.GamePhase.START, CardEnums.GamePhase.MAIN])
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.AWAITING_ACTION)
	# Start phase drew opponent-monster-rank (1) cards.
	assert_int(state.players[0].hand.size()).is_equal(1)
	# Confirmation steps flowed through the input port.
	assert_bool(input.count_calls("confirm_step") > 0).is_true()


func test_pass_runs_counter_end_and_next_turn() -> void:
	var input := ScriptedPlayerInput.new()
	var state := _flow_state()
	var tm := States.make_turn_manager(state, input)
	tm.start_game(0)
	var counter_results: Array = []
	tm.events.counter_failed.connect(func(_pid: int, _cp: int, _t: int, _rt: int, _et: int) -> void:
		counter_results.append("failed"))

	await tm.submit_action(CardEnums.ActionType.PASS)

	# Counter failed (no battle cards on p0's board), end phase advanced p0's
	# monster 1 -> 2, hand refilled to 5, and the next turn reached p1's MAIN.
	assert_array(counter_results).contains_exactly(["failed"])
	assert_int(state.players[0].monster_zone).is_equal(2)
	assert_int(state.players[0].hand.size()).is_equal(5)
	assert_int(state.turn_number).is_equal(2)
	assert_int(state.current_player_id).is_equal(1)
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.AWAITING_ACTION)


func test_submit_action_ignored_unless_awaiting() -> void:
	var state := _flow_state()
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	# Before start_game: IDLE — submit must be dropped.
	await tm.submit_action(CardEnums.ActionType.PASS)
	assert_int(state.turn_number).is_equal(0)

	tm.start_game(0)
	tm.is_game_over = true
	tm.flow_state = TurnManager.FlowState.GAME_OVER
	await tm.submit_action(CardEnums.ActionType.PASS)
	assert_int(state.current_phase).is_equal(CardEnums.GamePhase.MAIN)


func test_gain_rage_action_loops_back_to_awaiting() -> void:
	var state := _flow_state({"p0": {
		"hand": [Cards.monster()],
		"main_deck": [Cards.battle(1, 5000, "D1")],
	}})
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	tm.start_game(0)

	await tm.submit_action(CardEnums.ActionType.GAIN_RAGE, {"hand_index": state.players[0].hand.size() - 1})

	assert_int(state.players[0].rage).is_equal(1)
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.AWAITING_ACTION)
	assert_int(state.current_phase).is_equal(CardEnums.GamePhase.MAIN)


func test_invasion_victory_ends_game() -> void:
	var state := _flow_state({"p0": {
		"monster_zone": 8,
		"hand": [Cards.battle(1, 5000, "INV", [], 1)],
	}})
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	tm.start_game(0)
	var endings: Array = []
	tm.game_ended.connect(func(winner_id: int, reason: String) -> void: endings.append([winner_id, reason]))

	var invade_index: int = state.players[0].hand.size() - 1
	await tm.submit_action(CardEnums.ActionType.INVADE, {"hand_index": invade_index})

	assert_int(endings.size()).is_equal(1)
	assert_int(endings[0][0]).is_equal(0)
	assert_bool(tm.is_game_over).is_true()
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.GAME_OVER)


func test_save_restore_resume_round_trip() -> void:
	# Build a mid-game state from real card data (the serializer resolves
	# cards by id through CardData).
	var g1: Dictionary = CardData.get_card_by_id("ESD01-001")
	var battle: Dictionary = CardData.get_card_by_id("ESD01-005")
	assert_bool(g1.is_empty()).is_false()
	assert_bool(battle.is_empty()).is_false()

	var state := GameState.new()
	state.turn_number = 4
	state.current_player_id = 1
	for pid in range(2):
		var p := state.players[pid]
		p.current_monster = g1.duplicate(true)
		p.monster_zone = 3 if pid == 0 else 5
		p.rage = pid + 1
		p.hand.append(battle.duplicate(true))
		p.main_deck.append(battle.duplicate(true))
		p.push_zone_card(2, battle.duplicate(true))

	var deck_names: Array[String] = ["A", "B"]
	var save := GameSerializer.serialize_game_state(state, 0, "solo", "", deck_names)

	var tm := TurnManager.new()
	tm.player_input = ScriptedPlayerInput.new()
	tm.setup_from_save(save)

	for pid in range(2):
		var restored := tm.game_state.players[pid]
		assert_str(str(restored.current_monster.get("id"))).contains("ESD01-001")
		assert_int(restored.monster_zone).is_equal(3 if pid == 0 else 5)
		assert_int(restored.rage).is_equal(pid + 1)
		assert_int(restored.hand.size()).is_equal(1)
		assert_bool(restored.zone_has_cards(2)).is_true()

	# Resume into the saved player's main phase and accept an action.
	tm.resume_to_main_phase(1)
	assert_int(tm.game_state.turn_number).is_equal(4)
	assert_int(tm.game_state.current_player_id).is_equal(1)
	assert_int(tm.game_state.current_phase).is_equal(CardEnums.GamePhase.MAIN)
	assert_int(tm.flow_state).is_equal(TurnManager.FlowState.AWAITING_ACTION)
