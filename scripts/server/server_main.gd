extends Node

## Entry point for the dedicated headless game server. Owns the
## ServerConnectionManager (shared WebSocket transport) and the room map,
## and speaks the JSON control plane with clients:
##
##   C->S HELLO {version, name}        -> S->C WELCOME {peer_id} | ERROR
##   C->S CREATE {public, mode}        -> S->C ROOM_CREATED {room} + SEATED
##   C->S JOIN {room}                  -> S->C SEATED {room, player_id, token}
##   C->S DECK {deck_name, monster, main}
##   (both decks in)                   -> S->C START {player_id, mode, opponent_name}
##   C->S BOARD_READY {}               -> (both ready) match begins
##   C->S BUSY {} / READY {}           -> lobby-bot away/back (gates match start)
##   S->C PEER_PRESENT {player_id, connected}
##   S->C LOBBY {opponent_*, you_deck_ready}
##
## A plain HTTP listener on port+1 serves "/" (status text, polled by the
## Discord bot) and "/rooms?mode=X" (public room list JSON) — same contract
## as the relay's HTTP endpoint.
##
## Reconnect: C->S RECONNECT {room, token} re-seats a returning player (the
## token from SEATED is the credential); the client then requests a resync
## through the normal MultiplayerSync path. A periodic sweep GCs rooms whose
## players are all gone past the hold window.
##
## Run: godot --headless --path . scenes/server/ServerMain.tscn -- --port 12091

const DEFAULT_PORT := 12091
const ROOM_CODE_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const SWEEP_INTERVAL_S := 30.0
const MID_GAME_HOLD_S := 600.0 # both players gone mid-match: hold 10 min for reconnect
const POST_GAME_HOLD_S := 300.0 # game over, both gone: hold 5 min (rematch grace)

var GAME_VERSION: String = ProjectSettings.get_setting("application/config/version", "unknown")

var conn_mgr: ServerConnectionManager
var rooms: Dictionary = {} # code -> GameRoom
var _grace_override: float = -1.0
var _stats_enabled: bool = true
var _conn_room: Dictionary = {} # conn_id -> room code
var _conn_hello: Dictionary = {} # conn_id -> {name, version}

@onready var rooms_node: Node = $Rooms


func _ready() -> void:
	var port := DEFAULT_PORT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--grace="): # test runs: shorten the claim-win grace
			_grace_override = float(arg.get_slice("=", 1))
		elif arg == "--no-stats": # test runs: never POST results to the stats API
			_stats_enabled = false
	conn_mgr = ServerConnectionManager.new()
	conn_mgr.name = "ConnectionManager"
	add_child(conn_mgr)
	conn_mgr.control_received.connect(_on_control)
	conn_mgr.binary_received.connect(_on_binary)
	conn_mgr.connection_closed.connect(_on_connection_closed)
	if conn_mgr.listen(port) != OK:
		get_tree().quit(1)
		return
	if _http.listen(port + 1) != OK:
		push_error("[Server] HTTP listener failed on port %d" % (port + 1))
	else:
		print("[Server] HTTP status/rooms endpoint on port %d" % (port + 1))
	print("[Server] Godzilla TCG dedicated server v%s ready" % GAME_VERSION)


func _on_control(conn_id: int, msg: Dictionary) -> void:
	var msg_type := str(msg.get("type", ""))

	if msg_type == "HELLO":
		var version := str(msg.get("version", ""))
		if version != GAME_VERSION:
			conn_mgr.send_control(conn_id, {"type": "ERROR", "code": "version", "server_version": GAME_VERSION})
			conn_mgr.close_connection(conn_id, 4001, "Version mismatch")
			return
		_conn_hello[conn_id] = {"name": ChatFilter.filter(str(msg.get("name", "Player"))), "version": version}
		conn_mgr.send_control(conn_id, {"type": "WELCOME", "peer_id": conn_id})
		return

	if not _conn_hello.has(conn_id):
		conn_mgr.send_control(conn_id, {"type": "ERROR", "code": "no_hello"})
		return

	match msg_type:
		"CREATE":
			var room := _create_room(str(msg.get("mode", "")), bool(msg.get("public", false)))
			conn_mgr.send_control(conn_id, {"type": "ROOM_CREATED", "room": room.code})
			_seat(conn_id, room)
		"JOIN":
			var room: GameRoom = rooms.get(str(msg.get("room", "")).to_upper(), null)
			if room == null:
				conn_mgr.send_control(conn_id, {"type": "ERROR", "code": "not_found"})
				return
			if not room.has_space() or room.match_started:
				conn_mgr.send_control(conn_id, {"type": "ERROR", "code": "full"})
				return
			_seat(conn_id, room)
		"RECONNECT":
			var room: GameRoom = rooms.get(str(msg.get("room", "")).to_upper(), null)
			if room == null:
				conn_mgr.send_control(conn_id, {"type": "ERROR", "code": "not_found"})
				return
			var seat := room.reconnect_player(conn_id, str(msg.get("token", "")))
			if seat.is_empty():
				conn_mgr.send_control(conn_id, {"type": "ERROR", "code": "bad_token"})
				return
			_conn_room[conn_id] = room.code
			conn_mgr.send_control(conn_id, {
				"type": "SEATED",
				"room": room.code,
				"player_id": seat["player_id"],
				"token": seat["token"],
			})
		"DECK":
			var room := _room_for(conn_id)
			if room:
				room.set_deck(conn_id, msg)
		"BOARD_READY":
			var room := _room_for(conn_id)
			if room:
				room.mark_board_ready(conn_id)
		"BUSY":
			var room := _room_for(conn_id)
			if room:
				room.set_lobby_ready(conn_id, false)
		"READY":
			var room := _room_for(conn_id)
			if room:
				room.set_lobby_ready(conn_id, true)
		_:
			push_warning("[Server] Unknown control type '%s' from %d" % [msg_type, conn_id])


func _seat(conn_id: int, room: GameRoom) -> void:
	var seat := room.seat_player(conn_id, _conn_hello[conn_id]["name"])
	if seat.is_empty():
		conn_mgr.send_control(conn_id, {"type": "ERROR", "code": "full"})
		return
	_conn_room[conn_id] = room.code
	conn_mgr.send_control(conn_id, {
		"type": "SEATED",
		"room": room.code,
		"player_id": seat["player_id"],
		"token": seat["token"],
	})


func _on_binary(conn_id: int, pkt: PackedByteArray) -> void:
	var room := _room_for(conn_id)
	if room:
		room.handle_binary(conn_id, pkt)


func _on_connection_closed(conn_id: int) -> void:
	_conn_hello.erase(conn_id)
	var room := _room_for(conn_id)
	_conn_room.erase(conn_id)
	if room:
		room.on_connection_closed(conn_id)


func _room_for(conn_id: int) -> GameRoom:
	return rooms.get(_conn_room.get(conn_id, ""), null)


func _create_room(mode: String, is_public: bool) -> GameRoom:
	var code := _generate_room_code()
	var room := GameRoom.new()
	room.name = "R_" + code
	rooms_node.add_child(room)
	room.setup(code, mode, conn_mgr)
	room.is_public = is_public
	room.stats_enabled = _stats_enabled
	if _grace_override > 0:
		room.grace_seconds = _grace_override
	room.emptied.connect(_on_room_emptied.bind(code))
	rooms[code] = room
	print("[Server] Room %s created (mode='%s' public=%s, %d total)" % [code, mode, is_public, rooms.size()])
	return room


func _on_room_emptied(code: String) -> void:
	var room: GameRoom = rooms.get(code, null)
	if room == null:
		return
	rooms.erase(code)
	room.teardown()
	print("[Server] Room %s closed (%d remain)" % [code, rooms.size()])


func _generate_room_code() -> String:
	while true:
		var code := ""
		for i in 6:
			code += ROOM_CODE_CHARS[randi() % ROOM_CODE_CHARS.length()]
		if not rooms.has(code):
			return code
	return "" # unreachable


## GC rooms whose players are all gone past the hold window (mid-match rooms
## are held longer so a double-drop can still reconnect).
func _sweep_rooms() -> void:
	var now := Time.get_ticks_msec()
	for code in rooms.keys():
		var room: GameRoom = rooms[code]
		if room.is_abandoned(now, MID_GAME_HOLD_S, POST_GAME_HOLD_S):
			rooms.erase(code)
			room.teardown()
			print("[Server] Room %s swept (abandoned; %d remain)" % [code, rooms.size()])


# --- HTTP status + public room listing (relay-compatible contract) ---

var _http := TCPServer.new()
var _http_conns: Array = [] # of {tcp: StreamPeerTCP, buf: String, started_ms: int}


func get_public_rooms(mode_filter: String) -> Array:
	var out: Array = []
	for code in rooms:
		var room: GameRoom = rooms[code]
		if not room.is_public or room.match_started or not room.has_space():
			continue
		if not mode_filter.is_empty() and room.game_mode != mode_filter:
			continue
		var creator = room.seats[0] if room.seats[0] != null else room.seats[1]
		if creator == null:
			continue
		out.append({"code": code, "name": creator["name"], "players": 1, "mode": room.game_mode})
	return out


var _sweep_elapsed: float = 0.0


func _process(delta: float) -> void:
	_sweep_elapsed += delta
	if _sweep_elapsed >= SWEEP_INTERVAL_S:
		_sweep_elapsed = 0.0
		_sweep_rooms()

	while _http.is_connection_available():
		_http_conns.append({"tcp": _http.take_connection(), "buf": "", "started_ms": Time.get_ticks_msec()})

	var done: Array = []
	for conn in _http_conns:
		var tcp: StreamPeerTCP = conn["tcp"]
		tcp.poll()
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			done.append(conn)
			continue
		var available := tcp.get_available_bytes()
		if available > 0:
			conn["buf"] += tcp.get_utf8_string(available)
		if conn["buf"].contains("\r\n\r\n"):
			_answer_http(tcp, conn["buf"])
			tcp.disconnect_from_host()
			done.append(conn)
		elif Time.get_ticks_msec() - conn["started_ms"] > 5000 or conn["buf"].length() > 4096:
			tcp.disconnect_from_host()
			done.append(conn)
	for conn in done:
		_http_conns.erase(conn)


func _answer_http(tcp: StreamPeerTCP, request: String) -> void:
	var request_line := request.get_slice("\r\n", 0)
	var target := request_line.get_slice(" ", 1) # "GET /rooms?mode=x HTTP/1.1"
	var path := target.get_slice("?", 0)
	var body: String
	var content_type: String
	if path == "/rooms":
		var mode_filter := ""
		if target.contains("?"):
			for param in target.get_slice("?", 1).split("&"):
				if param.begins_with("mode="):
					mode_filter = param.get_slice("=", 1).uri_decode()
		body = JSON.stringify(get_public_rooms(mode_filter))
		content_type = "application/json"
	else:
		# Keep the "N active rooms" phrasing — the Discord status bot regexes
		# it. The version makes deploys verifiable with a curl.
		body = "Godzilla TCG server v%s running. %d active rooms.\n" % [GAME_VERSION, rooms.size()]
		content_type = "text/plain"
	var response := "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [
		content_type, body.to_utf8_buffer().size(), body]
	tcp.put_data(response.to_utf8_buffer())
