extends Node

## Manages multiplayer connections using ENetMultiplayerPeer (LAN) or
## RelayMultiplayerPeer (Online via WebSocket relay server).
## Registered as an autoload singleton. Contains no game logic —
## just connection lifecycle, player assignment, and session state.

enum Mode {SOLO, HOST, CLIENT, ONLINE_HOST, ONLINE_CLIENT}

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal game_starting()
signal version_mismatch(local_version: String, remote_version: String)
signal version_verified_ok()

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 2
const VERSION_TIMEOUT: float = 5.0
var GAME_VERSION: String = ProjectSettings.get_setting("application/config/version", "unknown")
const RELAY_HOST: String = "godzillatcg.com"
const RELAY_PORT: int = 12090
const WS_CONNECT_TIMEOUT: float = 10.0

var mode: Mode = Mode.SOLO
var local_player_id: int = -1
var host_peer_id: int = 1 ## Always peer 1 (server) for both LAN and relay
var peer_player_map: Dictionary = {} # {peer_id: player_id}
var opponent_connected: bool = false
var version_verified: bool = false
var _room_code: String = ""
var game_mode: String = ""  # "rumble", "no_rules", or "" (private/LAN)
var is_public_room: bool = false


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
## p_game_mode: "rumble" or "no_rules"
func host_public(p_game_mode: String = "rumble") -> Error:
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


## Fetch the list of public rooms from the relay server.
## Returns an Array of Dictionaries: [{"code": "ABC123", "players": 1, "mode": "rumble"}, ...]
## Returns an empty Array on failure.
## p_game_mode: filter to a specific mode, or "" for all modes.
func fetch_public_rooms(p_game_mode: String = "") -> Array:
	var http := HTTPRequest.new()
	add_child(http)
	var url := "http://%s:%d/rooms?version=%s" % [RELAY_HOST, RELAY_PORT, GAME_VERSION]
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
	_room_code = game_code
	var relay_peer := RelayMultiplayerPeer.new()
	var url := "ws://%s:%d/%s" % [RELAY_HOST, RELAY_PORT, game_code]
	var err := relay_peer.connect_as_client(url)
	if err != OK:
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
	peer_player_map.clear()
	opponent_connected = false
	version_verified = false
	_room_code = ""
	game_mode = ""
	is_public_room = false


func is_multiplayer() -> bool:
	return mode != Mode.SOLO


func is_host() -> bool:
	return mode == Mode.HOST or mode == Mode.ONLINE_HOST


func is_local_player_turn(current_player_id: int) -> bool:
	if mode == Mode.SOLO:
		return true
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


# --- Relay helpers ---

func _generate_room_code() -> String:
	const CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var code := ""
	for i in 6:
		code += CHARS[randi() % CHARS.length()]
	return code


## Waits for the RelayMultiplayerPeer to reach CONNECTION_CONNECTED.
## For the host, this happens when the WebSocket opens.
## For the client, this happens when the relay confirms the host is present.
func _wait_for_relay_connection(relay_peer: RelayMultiplayerPeer) -> Error:
	var elapsed := 0.0
	while elapsed < WS_CONNECT_TIMEOUT:
		var status := relay_peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			return OK
		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return ERR_CANT_CONNECT
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	return ERR_TIMEOUT


# --- Host callbacks ---

func _on_peer_connected(peer_id: int) -> void:
	# Assign the connecting peer as player 1
	peer_player_map[peer_id] = 1
	peer_player_map[multiplayer.get_unique_id()] = 0
	opponent_connected = true
	_rpc_assign_player.rpc_id(peer_id, 1)
	_rpc_assign_game_mode.rpc_id(peer_id, game_mode, is_public_room)
	_rpc_exchange_version.rpc_id(peer_id, GAME_VERSION)
	player_connected.emit(peer_id)
	_start_version_timeout()


func _on_peer_disconnected(peer_id: int) -> void:
	peer_player_map.erase(peer_id)
	opponent_connected = false
	player_disconnected.emit(peer_id)


# --- Client callbacks ---

## Client connected to the host (peer 1) — used for both LAN and relay.
func _on_connected_to_server() -> void:
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
func _rpc_exchange_version(remote_version: String) -> void:
	if remote_version != GAME_VERSION:
		version_mismatch.emit(GAME_VERSION, remote_version)
		disconnect_game()
		return
	version_verified = true
	version_verified_ok.emit()
