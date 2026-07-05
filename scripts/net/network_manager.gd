extends Node

## Manages multiplayer connections using ENetMultiplayerPeer (LAN) or
## RelayMultiplayerPeer (Online via WebSocket relay server).
## Registered as an autoload singleton. Contains no game logic —
## just connection lifecycle, player assignment, and session state.

enum Mode {SOLO, SOLO_BOT, HOST, CLIENT, ONLINE_HOST, ONLINE_CLIENT, ONLINE} # ONLINE = dedicated server (neither player is host)

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal player_reconnected(peer_id: int)
signal connection_failed()
signal game_starting()
signal version_mismatch(local_version: String, remote_version: String)
signal version_verified_ok()
signal match_declined()  ## emitted on the joined client when the host declined to start the match
signal server_seated(room: String, player_id: int)  ## dedicated server assigned us a seat
signal server_room_created(code: String)  ## dedicated server created our room
signal server_error(code: String)  ## dedicated server rejected a request
signal server_lobby_update(info: Dictionary)  ## pre-match seat/deck status from the dedicated server
signal server_peer_present(player_id: int, connected: bool, grace_s: float)  ## opponent dropped/returned mid-match (dedicated server)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 2
const VERSION_TIMEOUT: float = 5.0
var GAME_VERSION: String = ProjectSettings.get_setting("application/config/version", "unknown")
## Master switch for online play's backend. false = the WebSocket relay
## (host-client, today's production behavior). true = the dedicated game
## server (authoritative, validated, reconnectable) — flip once the server
## is deployed. The lobbies, room listing, and reconnect flows all branch
## on this; LAN is unaffected either way.
const USE_DEDICATED_SERVER: bool = false

const RELAY_HOST: String = "godzillatcg.com"
const RELAY_PORT: int = 12090
## Dedicated game server (replaces the relay for online play). One server
## runs per release channel — the HELLO handshake version-gates clients, so
## each build targets its own channel's port. Variables so tests/dev can
## retarget localhost (see --server-host/--server-port in _ready).
const SERVER_PORT_STABLE: int = 12101
const SERVER_PORT_UNSTABLE: int = 12111
var server_host: String = "godzillatcg.com"
var server_port: int = SERVER_PORT_UNSTABLE if GAME_VERSION.contains("unstable") else SERVER_PORT_STABLE
const WS_CONNECT_TIMEOUT: float = 10.0
const KEEPALIVE_INTERVAL: float = 25.0  ## Idle keepalive; stays under typical 30–60s proxy timeouts

var mode: Mode = Mode.SOLO
var local_player_id: int = -1
var host_peer_id: int = 1 ## Always peer 1 (server) for both LAN and relay
var peer_player_map: Dictionary = {} # {peer_id: player_id}
var opponent_connected: bool = false
var version_verified: bool = false
var is_in_game: bool = false  ## True while actively in GameBoard
var _room_code: String = ""
var game_mode: String = ""  # "rumble_west", "rumble_east", "no_rules", or "" (private/LAN)
var is_public_room: bool = false
var bot_config: BotConfig = BotConfig.normal()
var bot_difficulty: BotConfig.Difficulty = BotConfig.Difficulty.NORMAL
var bot_seed: int = -1  ## Deterministic RNG seed for bot games (-1 = auto-generate)
var server_peer: GameServerPeer  ## Live bridge to the dedicated server (Mode.ONLINE)
var room_token: String = ""  ## Reconnect credential issued by the dedicated server

# --- Lobby-bot game state (Play vs Bot While You Wait) ---
var _lobby_resume_mode: Mode = Mode.SOLO
var _lobby_resume_pid: int = -1
var _lobby_resume_active: bool = false
var _lobby_queued_deck_name: String = ""  ## Deck the host queued with; restored on exit so bot-rematch deck swaps don't leak into PvP
var _keepalive_elapsed: float = 0.0


func set_bot_difficulty(difficulty: BotConfig.Difficulty) -> void:
	bot_difficulty = difficulty
	bot_config = BotConfig.from_difficulty(difficulty)


# --- Lobby-bot game (Play vs Bot While You Wait) ---

## Switch to SOLO_BOT mode for an in-lobby bot match. The relay peer, room code,
## and host state are intentionally preserved so the lobby keeps accepting joins.
func enter_lobby_bot_game(difficulty: BotConfig.Difficulty) -> void:
	_lobby_resume_mode = mode
	_lobby_resume_pid = local_player_id
	_lobby_queued_deck_name = DecklistManager.get_player_deck_name(local_player_id)
	_lobby_resume_active = true
	mode = Mode.SOLO_BOT
	local_player_id = 0
	set_bot_difficulty(difficulty)
	# Dedicated server: gate the room so the match can't start while we're away.
	if server_peer != null:
		server_peer.send_control({"type": "BUSY"})


## Restore the saved lobby state. Does NOT touch the relay peer or room state —
## the lobby remains live across the bot match. Also restores the host's queued
## deck so any deck swaps during bot rematches don't carry into the PvP match.
func exit_lobby_bot_game() -> void:
	if not _lobby_resume_active:
		return
	mode = _lobby_resume_mode
	local_player_id = _lobby_resume_pid
	if not _lobby_queued_deck_name.is_empty():
		DecklistManager.select_deck_for_player(_lobby_resume_pid, _lobby_queued_deck_name)
	_lobby_resume_active = false
	_lobby_resume_mode = Mode.SOLO
	_lobby_resume_pid = -1
	_lobby_queued_deck_name = ""
	# Dedicated server: we're back in the lobby — allow the match to start.
	if mode == Mode.ONLINE and server_peer != null:
		server_peer.send_control({"type": "READY"})


func is_lobby_bot_game() -> bool:
	return _lobby_resume_active


func _ready() -> void:
	# Dev/test overrides for the dedicated server target, e.g. editor
	# Run Instances with "-- --server-host=127.0.0.1" to playtest against a
	# locally running server.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server-host="):
			server_host = arg.get_slice("=", 1)
			print("[NetworkManager] server_host override: %s" % server_host)
		elif arg.begins_with("--server-port="):
			server_port = int(arg.get_slice("=", 1))
			print("[NetworkManager] server_port override: %d" % server_port)


func _process(delta: float) -> void:
	# Idle keepalive — send a no-op text frame while idling so the relay/server
	# TCP path doesn't get killed by an idle proxy timeout. Relay: while
	# waiting for an opponent. Dedicated server: always (the server enforces
	# an idle timeout, so the heartbeat must keep flowing even mid-match
	# during long opponent turns).
	var peer := multiplayer.multiplayer_peer
	var idle := false
	if peer is RelayMultiplayerPeer:
		idle = not opponent_connected
	elif peer is GameServerPeer:
		idle = true
	if idle:
		_keepalive_elapsed += delta
		if _keepalive_elapsed >= KEEPALIVE_INTERVAL:
			_keepalive_elapsed = 0.0
			peer.send_keepalive()
	else:
		_keepalive_elapsed = 0.0


func change_scene(path: String) -> void:
	## Change scene safely — disables input on the current scene first to prevent
	## "_push_unhandled_input_internal: !is_inside_tree()" warnings.
	var tree := get_tree()
	var current := tree.current_scene
	if current:
		current.process_mode = Node.PROCESS_MODE_DISABLED
	# Defer to next frame so the process mode change takes effect first
	tree.call_deferred("change_scene_to_file", path)


# --- LAN ---

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	mode = Mode.HOST
	host_peer_id = 1
	local_player_id = 0
	peer_player_map[1] = 0 # Server's own peer ID is always 1
	return OK


func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	mode = Mode.CLIENT
	host_peer_id = 1
	return OK


# --- Online (WebSocket relay) ---

## Connect to the relay server and create a room. On success, get_game_code()
## returns the room code to share with the opponent.
func host_online() -> Error:
	_room_code = _generate_room_code()
	var relay_peer := RelayMultiplayerPeer.new()
	var url := "ws://%s:%d/%s" % [RELAY_HOST, RELAY_PORT, _room_code]
	var err := relay_peer.connect_as_host(url)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = relay_peer

	# Connect signals before waiting so we don't miss peer_connected
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Wait for WebSocket to open (host becomes CONNECTED immediately)
	err = await _wait_for_relay_connection(relay_peer)
	if err != OK:
		multiplayer.multiplayer_peer = null
		if multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.disconnect(_on_peer_connected)
		if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
		return err

	mode = Mode.ONLINE_HOST
	host_peer_id = 1
	local_player_id = 0
	peer_player_map[1] = 0 # Host is player 0
	return OK


## Connect to the relay server and create a public room. Same as host_online()
## but appends ?public=true so the relay server lists it for other players.
## p_game_mode: "rumble_west", "rumble_east", or "no_rules"
func host_public(p_game_mode: String = "rumble_west") -> Error:
	_room_code = _generate_room_code()
	game_mode = p_game_mode
	is_public_room = true
	var relay_peer := RelayMultiplayerPeer.new()
	var host_name := ChatFilter.filter(GameSettings.player_name).uri_encode()
	var url := "ws://%s:%d/%s?public=true&version=%s&name=%s&mode=%s" % [RELAY_HOST, RELAY_PORT, _room_code, GAME_VERSION, host_name, game_mode.uri_encode()]
	var err := relay_peer.connect_as_host(url)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = relay_peer

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	err = await _wait_for_relay_connection(relay_peer)
	if err != OK:
		multiplayer.multiplayer_peer = null
		if multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.disconnect(_on_peer_connected)
		if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
		return err

	mode = Mode.ONLINE_HOST
	host_peer_id = 1
	local_player_id = 0
	peer_player_map[1] = 0
	return OK


## Fetch the public room list — from the relay (which filters by the version
## param) or the dedicated server's HTTP endpoint on server_port + 1
## (versions are gated at HELLO there), depending on USE_DEDICATED_SERVER.
## Returns an Array of Dictionaries: [{"code": "ABC123", "players": 1, "mode": "rumble_west"}, ...]
## Returns an empty Array on failure.
## p_game_mode: filter to a specific mode, or "" for all modes.
func fetch_public_rooms(p_game_mode: String = "") -> Array:
	var http := HTTPRequest.new()
	add_child(http)
	var url: String
	if USE_DEDICATED_SERVER:
		url = "http://%s:%d/rooms?version=%s" % [server_host, server_port + 1, GAME_VERSION]
	else:
		url = "http://%s:%d/rooms?version=%s" % [RELAY_HOST, RELAY_PORT, GAME_VERSION]
	if not p_game_mode.is_empty():
		url += "&mode=%s" % p_game_mode.uri_encode()
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		return []
	var result: Array = await http.request_completed
	http.queue_free()
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	if response_code != 200:
		return []
	var json_str := body.get_string_from_utf8()
	var parsed = JSON.parse_string(json_str)
	if parsed is Array:
		return parsed
	return []


## Connect to a host's room via the relay server using their room code.
func join_online(game_code: String) -> Error:
	print("[NetworkManager] join_online('%s') start" % game_code)
	_room_code = game_code
	var relay_peer := RelayMultiplayerPeer.new()
	var url := "ws://%s:%d/%s" % [RELAY_HOST, RELAY_PORT, game_code]
	var err := relay_peer.connect_as_client(url)
	if err != OK:
		print("[NetworkManager] join_online: connect_as_client failed: %d" % err)
		return err

	multiplayer.multiplayer_peer = relay_peer

	# Set mode before connecting signals — connected_to_server fires during the
	# await below, and listeners check is_multiplayer() which requires mode != SOLO.
	mode = Mode.ONLINE_CLIENT
	host_peer_id = 1

	# Connect signals before waiting — connected_to_server fires when the relay
	# peer transitions to CONNECTED (after the relay confirms the host is present).
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Wait for relay connection + host discovery
	err = await _wait_for_relay_connection(relay_peer)
	if err != OK:
		print("[NetworkManager] join_online: relay connection failed: %d" % err)
		multiplayer.multiplayer_peer = null
		if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
			multiplayer.connected_to_server.disconnect(_on_connected_to_server)
		if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
		if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
			multiplayer.server_disconnected.disconnect(_on_server_disconnected)
		mode = Mode.SOLO
		host_peer_id = 1
		return err
	print("[NetworkManager] join_online: connected OK, version_verified=%s" % version_verified)
	return OK


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# Disconnect signals safely
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	mode = Mode.SOLO
	host_peer_id = 1
	local_player_id = -1
	server_peer = null
	room_token = ""
	peer_player_map.clear()
	opponent_connected = false
	version_verified = false
	is_in_game = false
	_room_code = ""
	game_mode = ""
	is_public_room = false
	_lobby_resume_active = false
	_lobby_resume_mode = Mode.SOLO
	_lobby_resume_pid = -1
	_lobby_queued_deck_name = ""
	_keepalive_elapsed = 0.0


func is_multiplayer() -> bool:
	return mode != Mode.SOLO and mode != Mode.SOLO_BOT


func is_host() -> bool:
	return mode == Mode.HOST or mode == Mode.ONLINE_HOST


func is_local_player_turn(current_player_id: int) -> bool:
	if mode == Mode.SOLO:
		return true
	if mode == Mode.SOLO_BOT:
		return current_player_id == local_player_id
	return current_player_id == local_player_id


## Returns the game code to share with the opponent (room code for relay).
func get_game_code() -> String:
	return _room_code


func get_local_player_id() -> int:
	return local_player_id


func start_lan_game() -> void:
	game_starting.emit()
	_rpc_start_game.rpc()
	get_tree().change_scene_to_file("res://scenes/board/GameBoard.tscn")


# --- Online (dedicated server) ---

## Connect the control-plane bridge to the dedicated server. The server
## version-gates at HELLO, so a successful WELCOME implies version_verified.
func connect_to_server() -> Error:
	var peer := GameServerPeer.new()
	var url := "ws://%s:%d/" % [server_host, server_port]
	var err := peer.connect_to_server(url, GameSettings.player_name, GAME_VERSION)
	if err != OK:
		return err

	server_peer = peer
	peer.control_received.connect(_on_server_control)
	multiplayer.multiplayer_peer = peer
	mode = Mode.ONLINE
	host_peer_id = 1
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	err = await _wait_for_relay_connection(peer)
	if err != OK:
		print("[NetworkManager] connect_to_server failed: %d" % err)
		multiplayer.multiplayer_peer = null
		server_peer = null
		mode = Mode.SOLO
		return err
	version_verified = true
	print("[NetworkManager] Connected to dedicated server as peer %d" % multiplayer.get_unique_id())
	return OK


## Mid-game reconnect to the dedicated server: fresh bridge + RECONNECT with
## the seat token issued at SEATED. Preserves mode, player id, and in-game
## state. Returns OK once re-seated (SEATED received), or an error.
func reconnect_to_server() -> Error:
	if room_token.is_empty() or _room_code.is_empty():
		return ERR_UNCONFIGURED
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	server_peer = null

	var peer := GameServerPeer.new()
	var url := "ws://%s:%d/" % [server_host, server_port]
	var err := peer.connect_to_server(url, GameSettings.player_name, GAME_VERSION)
	if err != OK:
		return err
	server_peer = peer
	peer.control_received.connect(_on_server_control)
	multiplayer.multiplayer_peer = peer
	mode = Mode.ONLINE # No-op for in-session reconnects; needed after app restart
	host_peer_id = 1
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	err = await _wait_for_relay_connection(peer)
	if err != OK:
		multiplayer.multiplayer_peer = null
		server_peer = null
		return err

	# Re-seat with the token, then wait for SEATED (or an error/timeout).
	var outcome := {"done": false, "ok": false}
	var on_seated := func(_room: String, _pid: int) -> void:
		outcome["done"] = true
		outcome["ok"] = true
	var on_error := func(_code: String) -> void:
		outcome["done"] = true
	server_seated.connect(on_seated)
	server_error.connect(on_error)
	peer.send_control({"type": "RECONNECT", "room": _room_code, "token": room_token})
	var elapsed := 0.0
	while not outcome["done"] and elapsed < WS_CONNECT_TIMEOUT:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	server_seated.disconnect(on_seated)
	server_error.disconnect(on_error)
	if not outcome["ok"]:
		return ERR_CANT_CONNECT
	print("[NetworkManager] Reconnected to room %s as player %d" % [_room_code, local_player_id])
	return OK


## App-restart recovery: rejoin a dedicated-server match from a persisted
## session (room code + seat token). On success, loads the game board and
## pulls a full resync once the board chain exists.
func resume_online_session(room_code: String, token: String, p_game_mode: String, p_is_public: bool) -> Error:
	_room_code = room_code
	room_token = token
	game_mode = p_game_mode
	is_public_room = p_is_public
	var err := await reconnect_to_server()
	if err != OK:
		return err
	opponent_connected = true
	is_in_game = true
	change_scene("res://scenes/board/GameBoard.tscn")
	while true:
		var sync_node := get_node_or_null("/root/GameBoard/GameSession/MultiplayerSync")
		if sync_node != null:
			await get_tree().process_frame
			sync_node._rpc_request_resync.rpc_id(host_peer_id)
			break
		if server_peer == null:
			break
		await get_tree().process_frame
	return OK


func create_room(p_public: bool = false, p_mode: String = "") -> void:
	game_mode = p_mode
	is_public_room = p_public
	server_peer.send_control({"type": "CREATE", "public": p_public, "mode": p_mode})


func join_room(p_code: String) -> void:
	server_peer.send_control({"type": "JOIN", "room": p_code})


## Load a local decklist and submit it to the server for this match.
func send_deck_to_server(deck_name: String) -> bool:
	var data := DecklistManager.load_decklist(deck_name)
	if data.is_empty():
		return false
	server_peer.send_control({
		"type": "DECK",
		"deck_name": deck_name,
		"monster": data["monster"],
		"main": data["main"],
	})
	return true


func _on_server_control(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"SEATED":
			local_player_id = int(msg.get("player_id", -1))
			_room_code = str(msg.get("room", ""))
			room_token = str(msg.get("token", ""))
			peer_player_map[multiplayer.get_unique_id()] = local_player_id
			server_seated.emit(_room_code, local_player_id)
		"ROOM_CREATED":
			server_room_created.emit(str(msg.get("room", "")))
		"START":
			if is_lobby_bot_game():
				# Safety: the BUSY gate should prevent this; never yank the
				# player out of a bot game mid-match.
				push_warning("[NetworkManager] START received during lobby-bot game — ignoring")
				return
			game_mode = str(msg.get("mode", ""))
			opponent_connected = true
			is_in_game = true
			game_starting.emit()
			_start_online_game()
		"ERROR":
			push_warning("[NetworkManager] Server error: %s" % str(msg.get("code", "")))
			if str(msg.get("code", "")) == "version":
				version_mismatch.emit(GAME_VERSION, str(msg.get("server_version", "unknown")))
			server_error.emit(str(msg.get("code", "")))
		"LOBBY":
			opponent_connected = bool(msg.get("opponent_connected", false))
			server_lobby_update.emit(msg)
		"PEER_PRESENT":
			server_peer_present.emit(
				int(msg.get("player_id", -1)),
				bool(msg.get("connected", false)),
				float(msg.get("grace_remaining_s", 0.0)))
		_:
			pass # WELCOME is consumed by GameServerPeer itself


## Load the board, then tell the server it can start firing prompts — the
## server has no scene-load delay, so without this gate its first-player RPCs
## would arrive before the client's MultiplayerSync node exists.
func _start_online_game() -> void:
	change_scene("res://scenes/board/GameBoard.tscn")
	while get_node_or_null("/root/GameBoard/GameSession/MultiplayerSync") == null:
		if server_peer == null:
			return
		await get_tree().process_frame
	server_peer.send_control({"type": "BOARD_READY"})


# --- Reconnect ---

## Client-only: attempt to reconnect to an existing relay room.
## Closes the old dead peer and creates a fresh WebSocket connection
## while preserving mode, player_id, and is_in_game state.
func attempt_reconnect(game_code: String) -> Error:
	print("[NetworkManager] attempt_reconnect('%s') start" % game_code)
	# Close old dead peer without full state reset
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# Disconnect stale signals
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)

	# Create fresh relay peer
	_room_code = game_code
	var relay_peer := RelayMultiplayerPeer.new()
	var url := "ws://%s:%d/%s" % [RELAY_HOST, RELAY_PORT, game_code]
	var err := relay_peer.connect_as_client(url)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = relay_peer
	mode = Mode.ONLINE_CLIENT
	host_peer_id = 1

	# Connect fresh signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Wait for relay connection
	err = await _wait_for_relay_connection(relay_peer)
	if err != OK:
		print("[NetworkManager] attempt_reconnect: relay connection failed: %d" % err)
		multiplayer.multiplayer_peer = null
		if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
			multiplayer.connected_to_server.disconnect(_on_connected_to_server)
		if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
		if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
			multiplayer.server_disconnected.disconnect(_on_server_disconnected)
		return err

	print("[NetworkManager] attempt_reconnect: connected OK")
	return OK


# --- Relay helpers ---

func _generate_room_code() -> String:
	const CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var code := ""
	for i in 6:
		code += CHARS[randi() % CHARS.length()]
	return code


## Waits for a relay/server peer to reach CONNECTION_CONNECTED.
## Relay host: when the WebSocket opens. Relay client: when the relay
## confirms the host is present. Dedicated server: when WELCOME arrives.
func _wait_for_relay_connection(relay_peer: MultiplayerPeer) -> Error:
	var elapsed := 0.0
	var last_status := -1
	while elapsed < WS_CONNECT_TIMEOUT:
		var status := relay_peer.get_connection_status()
		if status != last_status:
			print("[NetworkManager] relay status: %d (elapsed=%.1fs)" % [status, elapsed])
			last_status = status
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			return OK
		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return ERR_CANT_CONNECT
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	return ERR_TIMEOUT


# --- Host callbacks ---

func _on_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] _on_peer_connected: peer=%d is_in_game=%s" % [peer_id, is_in_game])
	# Assign the connecting peer as the other player
	var client_pid := 1 - local_player_id
	peer_player_map[peer_id] = client_pid
	peer_player_map[multiplayer.get_unique_id()] = local_player_id
	opponent_connected = true
	_rpc_assign_player.rpc_id(peer_id, client_pid)
	_rpc_assign_game_mode.rpc_id(peer_id, game_mode, is_public_room)
	_rpc_exchange_version.rpc_id(peer_id, GAME_VERSION)
	if is_in_game:
		player_reconnected.emit(peer_id)
	else:
		player_connected.emit(peer_id)
	_start_version_timeout()


func _on_peer_disconnected(peer_id: int) -> void:
	peer_player_map.erase(peer_id)
	opponent_connected = false
	version_verified = false
	player_disconnected.emit(peer_id)


# --- Client callbacks ---

## Client connected to the host (peer 1) — used for both LAN and relay.
func _on_connected_to_server() -> void:
	print("[NetworkManager] _on_connected_to_server: connected to host (peer %d)" % host_peer_id)
	opponent_connected = true
	_rpc_exchange_version.rpc_id(host_peer_id, GAME_VERSION)
	player_connected.emit(host_peer_id)
	_start_version_timeout()


func _on_connection_failed() -> void:
	disconnect_game()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	opponent_connected = false
	player_disconnected.emit(host_peer_id)


# --- RPCs ---

@rpc("any_peer", "call_remote", "reliable")
func _rpc_assign_player(pid: int) -> void:
	# Client receives its player ID from the host
	local_player_id = pid


@rpc("any_peer", "call_remote", "reliable")
func _rpc_start_game() -> void:
	# Client receives signal to start the game
	get_tree().change_scene_to_file("res://scenes/board/GameBoard.tscn")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_assign_game_mode(p_game_mode: String, p_is_public: bool) -> void:
	game_mode = p_game_mode
	is_public_room = p_is_public


func _start_version_timeout() -> void:
	await get_tree().create_timer(VERSION_TIMEOUT).timeout
	if not version_verified and opponent_connected:
		version_mismatch.emit(GAME_VERSION, "unknown")
		disconnect_game()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_peer_leaving() -> void:
	opponent_connected = false
	player_disconnected.emit(multiplayer.get_remote_sender_id())


func notify_leaving() -> void:
	if multiplayer.multiplayer_peer and opponent_connected:
		_rpc_peer_leaving.rpc()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_decline_match() -> void:
	match_declined.emit()


## Host-side: tell the joined client we're not starting the match.
func notify_match_declined() -> void:
	if not multiplayer.multiplayer_peer or not opponent_connected:
		return
	for peer_id in peer_player_map.keys():
		if peer_id != multiplayer.get_unique_id():
			_rpc_decline_match.rpc_id(peer_id)
			break


@rpc("any_peer", "call_remote", "reliable")
func _rpc_exchange_version(remote_version: String) -> void:
	print("[NetworkManager] _rpc_exchange_version: remote='%s' local='%s'" % [remote_version, GAME_VERSION])
	if remote_version != GAME_VERSION:
		version_mismatch.emit(GAME_VERSION, remote_version)
		disconnect_game()
		return
	version_verified = true
	version_verified_ok.emit()
