extends Node

## Headless protocol test client for the dedicated server. Connects, creates
## or joins a room (room code handed off via a temp file), submits a deck,
## and builds a stub GameBoard chain that speaks the real MultiplayerSync
## contract.
##
## Default mode: handshake smoke — exits 0 once it has applied a state
## broadcast (and, when it is the active player, received an action context).
##
## --play mode: full random-game harness — plays uniformly random legal
## actions and answers every prompt type with a random valid response until
## the match ends (the creator concedes if the game passes MAX_TURNS).
## The runner script greps the logs for [DESYNC] / SCRIPT ERROR afterwards.
##
## Run (two processes, after starting ServerMain):
##   godot --headless --path . scenes/server/tests/HeadlessTestClient.tscn -- --create [--play] [--seed=N]
##   godot --headless --path . scenes/server/tests/HeadlessTestClient.tscn -- --join [--play] [--seed=N]

const STUB_BOARD := preload("res://scenes/server/tests/stub_client_board.gd")
const GAME_SESSION := preload("res://scripts/session/game_session.gd")
const MULTIPLAYER_SYNC := preload("res://scripts/session/multiplayer_sync.gd")
const CODE_FILE := "/tmp/godzilla_test_room_code.txt"
const HANDSHAKE_TIMEOUT_S := 30.0
const PLAY_TIMEOUT_S := 600.0
const MAX_TURNS := 100

var peer: GameServerPeer
var board: Node
var session_node: GameSession
var sync_node: MultiplayerSync
var is_creator := false
var play_mode := false
var rng := RandomNumberGenerator.new()
var my_pid := -1
var got_state := false
var got_action_context := false
var answered_first_player := false
var match_over := false
var actions_submitted := 0
var conceded := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_creator = "--create" in args
	play_mode = "--play" in args
	rng.randomize()
	for arg in args:
		if arg.begins_with("--seed="):
			rng.seed = int(arg.get_slice("=", 1)) + (0 if is_creator else 1)
	if is_creator and FileAccess.file_exists(CODE_FILE):
		DirAccess.remove_absolute(CODE_FILE)

	_build_client_chain()
	await get_tree().process_frame

	peer = GameServerPeer.new()
	peer.control_received.connect(_on_control)
	var version: String = ProjectSettings.get_setting("application/config/version", "unknown")
	var pname := "Creator" if is_creator else "Joiner"
	var err := peer.connect_to_server("ws://127.0.0.1:12091/", pname, version)
	if err != OK:
		_fail("connect error %d" % err)
		return
	multiplayer.multiplayer_peer = peer

	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		await get_tree().process_frame
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_fail("connection dropped during handshake")
		return
	print("[TestClient %s] Connected as peer %d" % [_tag(), peer.get_unique_id()])

	if is_creator:
		peer.send_control({"type": "CREATE", "public": "--public" in args, "mode": "rumble_west" if "--public" in args else ""})
	else:
		var code := await _wait_for_code_file()
		if code.is_empty():
			_fail("no room code file")
			return
		peer.send_control({"type": "JOIN", "room": code})

	_run_watchdog()


func _build_client_chain() -> void:
	board = Node.new()
	board.set_script(STUB_BOARD)
	board.name = "GameBoard"
	session_node = GAME_SESSION.new()
	session_node.name = "GameSession"
	session_node.client_players = [PlayerState.new(0), PlayerState.new(1)]
	sync_node = MULTIPLAYER_SYNC.new()
	sync_node.name = "MultiplayerSync"
	session_node.add_child(sync_node)
	board.add_child(session_node)
	get_tree().root.add_child.call_deferred(board)
	board.prompt_received.connect(_on_prompt)
	board.action_context_received.connect(_on_action_context)
	board.state_applied.connect(func() -> void: got_state = true)
	board.match_ended.connect(func(w: int, r: String) -> void:
		print("[TestClient %s] Match ended: winner=%d reason=%s (after %d actions)" % [_tag(), w, r, actions_submitted])
		match_over = true)


func _on_control(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"ROOM_CREATED":
			var code := str(msg.get("room", ""))
			print("[TestClient %s] Room created: %s" % [_tag(), code])
			var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
			f.store_string(code)
			f.close()
		"SEATED":
			my_pid = int(msg.get("player_id", -1))
			board.local_player_id = my_pid
			print("[TestClient %s] Seated as player %d (token=%s...)" % [_tag(), my_pid, str(msg.get("token", "")).left(8)])
			var decks := DecklistManager.get_all_decklists()
			if decks.is_empty():
				_fail("no decklists available")
				return
			var deck_name: String = decks[rng.randi() % decks.size()] if play_mode else decks[0]
			var data := DecklistManager.load_decklist(deck_name)
			peer.send_control({"type": "DECK", "deck_name": deck_name, "monster": data["monster"], "main": data["main"]})
			print("[TestClient %s] Sent deck '%s'" % [_tag(), deck_name])
		"START":
			print("[TestClient %s] START received (pid=%d mode='%s' vs '%s')" % [
				_tag(), int(msg.get("player_id", -1)), str(msg.get("mode", "")), str(msg.get("opponent_name", ""))])
			peer.send_control({"type": "BOARD_READY"})
		"ERROR":
			_fail("server error: %s" % str(msg.get("code", "")))


# --- Prompt answering (random valid responses) ---

func _on_prompt(kind: String, args: Array) -> void:
	print("[TestClient %s] Prompt: %s %s" % [_tag(), kind, str(args).left(120)])
	match kind:
		"first_player_choice":
			answered_first_player = true
			sync_node._rpc_first_player_choice_resolved.rpc_id(1, rng.randi() % 2)
		"first_player_waiting":
			pass
		"confirmation":
			sync_node._rpc_confirmation_resolved.rpc_id(1)
		"hand_discard":
			var count := int(args[0])
			var hand: Array = session_node.client_players[my_pid].hand
			var indices: Array[int] = []
			var pool := range(hand.size())
			pool.shuffle()
			for i in range(mini(count, hand.size())):
				indices.append(pool[i])
			sync_node._rpc_hand_discard_resolved.rpc_id(1, JSON.stringify(indices))
		"hand_card_selection":
			var valid: Array = JSON.parse_string(args[0])
			var allow_skip: bool = args[2]
			if valid.is_empty() or (allow_skip and rng.randf() < 0.3):
				sync_node._rpc_hand_card_selection_resolved.rpc_id(1, -1)
			else:
				sync_node._rpc_hand_card_selection_resolved.rpc_id(1, int(valid[rng.randi() % valid.size()]))
		"deck_search":
			var matching: Array = JSON.parse_string(args[0])
			var allow_skip: bool = args[3]
			if matching.is_empty() or (allow_skip and rng.randf() < 0.2):
				sync_node._rpc_deck_search_resolved.rpc_id(1, "")
			else:
				var id := str(matching[rng.randi() % matching.size()])
				var cards := StateCodec.ids_to_cards([id])
				sync_node._rpc_deck_search_resolved.rpc_id(1, JSON.stringify(cards[0]) if not cards.is_empty() else "")
		"deck_arrange":
			# Keep everything in the given order, discard nothing.
			var ids: Array = JSON.parse_string(args[0])
			var cards := StateCodec.ids_to_cards(ids)
			sync_node._rpc_deck_arrange_resolved.rpc_id(1, JSON.stringify(cards), "[]")
		"card_select":
			var matching: Array = JSON.parse_string(args[0])
			var min_count := int(args[3])
			var picks: Array = []
			var pool := matching.duplicate()
			pool.shuffle()
			for i in range(mini(min_count, pool.size())):
				picks.append(pool[i])
			sync_node._rpc_card_select_resolved.rpc_id(1, JSON.stringify(picks))
		"zone_target":
			var zones: Array = JSON.parse_string(args[1])
			var allow_skip: bool = args[3]
			if zones.is_empty() or (allow_skip and rng.randf() < 0.2):
				sync_node._rpc_zone_target_resolved.rpc_id(1, -1)
			else:
				sync_node._rpc_zone_target_resolved.rpc_id(1, int(zones[rng.randi() % zones.size()]))
		"strategy_target":
			var indices: Array = JSON.parse_string(args[1])
			if indices.is_empty():
				sync_node._rpc_strategy_target_resolved.rpc_id(1, -1)
			else:
				sync_node._rpc_strategy_target_resolved.rpc_id(1, int(indices[rng.randi() % indices.size()]))
		"choice":
			var options: Array = JSON.parse_string(args[0])
			sync_node._rpc_choice_resolved.rpc_id(1, rng.randi() % maxi(1, options.size()))
		"monster_rankup":
			var valid: Array = JSON.parse_string(args[1])
			if valid.is_empty():
				sync_node._rpc_monster_rankup_resolved.rpc_id(1, -1)
			else:
				sync_node._rpc_monster_rankup_resolved.rpc_id(1, int(valid[rng.randi() % valid.size()]))
		_:
			push_warning("[TestClient %s] Unhandled prompt '%s' (args=%s)" % [_tag(), kind, args])


# --- Random legal action play ---

func _on_action_context(actions: Array, playable: Dictionary) -> void:
	got_action_context = true
	if not play_mode:
		print("[TestClient %s] Action context: %s" % [_tag(), str(actions)])
		return
	if match_over:
		return

	# Past the turn cap, the creator concedes to exercise the game-end path.
	if session_node.client_turn_number > MAX_TURNS and is_creator and not conceded:
		conceded = true
		print("[TestClient %s] Turn cap reached (turn %d) — conceding" % [_tag(), session_node.client_turn_number])
		sync_node._rpc_concede.rpc_id(1)
		return

	var action := int(actions[rng.randi() % actions.size()])
	var params := _params_for(action, playable)
	if params.is_empty() and action != CardEnums.ActionType.PASS:
		action = CardEnums.ActionType.PASS
		params = {}
	actions_submitted += 1
	print("[TestClient %s] Action #%d turn %d: %s %s" % [
		_tag(), actions_submitted, session_node.client_turn_number,
		CardEnums.ActionType.keys()[action], str(params)])
	sync_node._rpc_submit_action.rpc_id(1, action, JSON.stringify(params) if not params.is_empty() else "")


func _params_for(action: int, playable: Dictionary) -> Dictionary:
	match action:
		CardEnums.ActionType.PLAY_BATTLE:
			var cards: Array = playable.get("battle_cards", [])
			if cards.is_empty():
				return {}
			var hand_index := int(cards[rng.randi() % cards.size()])
			var hand: Array = session_node.client_players[my_pid].hand
			if hand_index >= hand.size():
				return {}
			var card_id: String = hand[hand_index].get("id", "")
			var zones: Array = playable.get("battle_zones", {}).get(card_id, [])
			if zones.is_empty():
				return {}
			return {"hand_index": hand_index, "zone_index": int(zones[rng.randi() % zones.size()])}
		CardEnums.ActionType.PLAY_STRATEGY:
			return _hand_index_params(playable, "strategy_cards")
		CardEnums.ActionType.GAIN_RAGE:
			return _hand_index_params(playable, "rage_cards")
		CardEnums.ActionType.PLAY_MONSTER:
			return _hand_index_params(playable, "monster_cards")
		CardEnums.ActionType.INVADE:
			return _hand_index_params(playable, "invade_cards")
	return {}


func _hand_index_params(playable: Dictionary, key: String) -> Dictionary:
	var cards: Array = playable.get(key, [])
	if cards.is_empty():
		return {}
	return {"hand_index": int(cards[rng.randi() % cards.size()])}


# --- Exit conditions ---

func _run_watchdog() -> void:
	var timeout := PLAY_TIMEOUT_S if play_mode else HANDSHAKE_TIMEOUT_S
	var elapsed := 0.0
	while elapsed < timeout:
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25
		if play_mode:
			if match_over:
				await get_tree().create_timer(2.0).timeout
				print("[TestClient %s] PASS (full game, %d actions submitted)" % [_tag(), actions_submitted])
				get_tree().quit(0)
				return
		elif got_state and (got_action_context or not answered_first_player):
			# Give the other client a moment to receive its own broadcasts.
			await get_tree().create_timer(2.0).timeout
			print("[TestClient %s] PASS (state=%s, action_context=%s, chose_first=%s)" % [
				_tag(), got_state, got_action_context, answered_first_player])
			get_tree().quit(0)
			return
	_fail("timeout (state=%s action_context=%s actions=%d turn=%d match_over=%s)" % [
		got_state, got_action_context, actions_submitted, session_node.client_turn_number, match_over])


func _wait_for_code_file() -> String:
	var elapsed := 0.0
	while elapsed < HANDSHAKE_TIMEOUT_S:
		if FileAccess.file_exists(CODE_FILE):
			var f := FileAccess.open(CODE_FILE, FileAccess.READ)
			var code := f.get_as_text().strip_edges()
			f.close()
			if not code.is_empty():
				return code
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25
	return ""


func _tag() -> String:
	return "creator" if is_creator else "joiner"


func _fail(why: String) -> void:
	push_error("[TestClient %s] FAIL: %s" % [_tag(), why])
	get_tree().quit(1)
