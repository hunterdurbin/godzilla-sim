extends GdUnitTestSuite

## GameLog tokens for the engine/card notes that used to reach log_message as
## a host-translated String (hunterdurbin/godzilla-sim-issue-tracker#45): each
## renders its STR text in the viewer's locale, survives the JSON round-trip a
## multiplayer client sees, and is recorded by a GameSession replay.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _tr(key: String) -> String:
	return TranslationServer.translate(key)


## Tokens reach a client as JSON (ints become floats).
func _json_round_trip(token: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(token))


func test_invade1_blocked_renders_its_str_text() -> void:
	var token := GameLog.invade1_blocked()
	assert_str(str(token["type"])).is_equal("invade1_blocked")
	assert_str(GameLog.render(token)).is_equal(_tr("STR_AH_INVADE1_BLOCKED"))


func test_end_phase_draw_blocked_renders_its_str_text() -> void:
	var token := GameLog.end_phase_draw_blocked()
	assert_str(str(token["type"])).is_equal("end_phase_draw_blocked")
	assert_str(GameLog.render(token)).is_equal(_tr("STR_AH_END_PHASE_DRAW_BLOCKED"))


func test_crawling_calamity_blocked_renders_its_str_text() -> void:
	var token := GameLog.crawling_calamity_blocked()
	assert_str(str(token["type"])).is_equal("crawling_calamity_blocked")
	assert_str(GameLog.render(token)).is_equal(_tr("STR_EFF_EBP04_078_BLOCKED"))


func test_crawling_calamity_teleported_renders_its_fmt_args() -> void:
	var token := GameLog.crawling_calamity_teleported(4, 7)
	assert_str(str(token["type"])).is_equal("crawling_calamity_teleported")
	var expected := _tr("STR_EFF_EBP04_078_TELEPORT_FMT") % [4, 7]
	assert_str(GameLog.render(token)).is_equal(expected)
	assert_str(GameLog.render(_json_round_trip(token))).is_equal(expected)


func test_inherited_life_milestone_renders_each_milestone() -> void:
	for milestone: int in [15, 22, 30]:
		var token := GameLog.inherited_life_milestone(milestone)
		assert_str(str(token["type"])).is_equal("inherited_life_milestone")
		var expected := _tr("STR_EFF_EBP04_089_MILESTONE_%d" % milestone)
		assert_str(GameLog.render(token)).is_equal(expected)
		assert_str(GameLog.render(_json_round_trip(token))).is_equal(expected)


func test_engine_emits_invade1_blocked_token() -> void:
	# EBP04-029 on player 1 blocks player 0's Invade-1 cost.
	var state := States.make_state({
		"p0": {"hand": [Cards.battle(1, 5000, "COST", [], 1)], "monster_zone": 1},
		"p1": {"current_monster": Real.instance("EBP04-029")},
	})
	var session := States.make_session(state)
	var tokens: Array[Dictionary] = []
	session["effect_handler"].log_message.connect(func(t: Dictionary) -> void: tokens.append(t))

	await session["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	assert_int(state.players[0].monster_zone).is_equal(1)
	assert_array(tokens).contains([GameLog.invade1_blocked()])


func test_engine_emits_end_phase_draw_blocked_token() -> void:
	# EBP04-030 (player 1's monster) stops player 0 drawing in the End Phase.
	var deck: Array = []
	for i in range(5):
		deck.append(Cards.battle(1))
	var state := States.make_state({
		"p0": {"hand": [Cards.battle(1)], "main_deck": deck},
		"p1": {"current_monster": Real.instance("EBP04-030")},
	})
	var session := States.make_session(state)
	var tokens: Array[Dictionary] = []
	session["effect_handler"].log_message.connect(func(t: Dictionary) -> void: tokens.append(t))

	session["action_handler"].execute_end_phase_draw(state)

	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_array(tokens).contains([GameLog.end_phase_draw_blocked()])


func test_game_session_replay_keeps_invade1_blocked_line() -> void:
	var state := States.make_state({
		"p0": {"hand": [Cards.battle(1, 5000, "COST", [], 1)], "monster_zone": 1},
		"p1": {"current_monster": Real.instance("EBP04-029")},
	})
	var tm := States.make_turn_manager(state)
	# GameSession._ready checks its scene contract (GameBoard parent,
	# MultiplayerSync child); satisfy it so the test runs clean.
	var board: Node = auto_free(Node.new())
	board.name = "GameBoard"
	var game_session := GameSession.new()
	var sync := Node.new()
	sync.name = "MultiplayerSync"
	game_session.add_child(sync)
	board.add_child(game_session)
	add_child(board)
	game_session.turn_manager = tm
	game_session.events = tm.events
	var recorder := game_session.setup_replay_recorder(false)

	await tm.action_handler.execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)

	var replay := recorder.finish(-1, "", 0)
	var lines: Array = []
	for snap: Dictionary in replay.snapshots:
		lines.append_array(snap.get("log_lines", []))
	assert_array(lines).contains([GameLog.invade1_blocked()])
	game_session.turn_manager = null
	tm.teardown()
