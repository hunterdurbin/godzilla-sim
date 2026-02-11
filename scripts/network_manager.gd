extends Node

## Manages multiplayer connections using ENetMultiplayerPeer (LAN) or
## WebSocketMultiplayerPeer (Online via relay server).
## Registered as an autoload singleton. Contains no game logic —
## just connection lifecycle, player assignment, and session state.

enum Mode {SOLO, HOST, CLIENT, ONLINE_HOST, ONLINE_CLIENT}

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal game_starting()
signal version_mismatch(local_version: String, remote_version: String)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 2
const VERSION_TIMEOUT: float = 5.0
var GAME_VERSION: String = ProjectSettings.get_setting("application/config/version", "unknown")
const RELAY_HOST: String = "godzillatcg.com"
const RELAY_PORT: int = 9090
const WS_CONNECT_TIMEOUT: float = 10.0

var mode: Mode = Mode.SOLO
var local_player_id: int = -1
var host_peer_id: int = 1 ## Peer 1 for LAN (server), peer 2 for relay
var peer_player_map: Dictionary = {} # {peer_id: player_id}
var opponent_connected: bool = false
var version_verified: bool = false
var _room_code: String = ""


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
	var ws_peer := WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d/%s" % [RELAY_HOST, RELAY_PORT, _room_code]
	var err := ws_peer.create_client(url)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = ws_peer

	# Wait for relay to assign our peer ID
	err = await _wait_for_ws_connection()
	if err != OK:
		multiplayer.multiplayer_peer = null
		return err

	host_peer_id = multiplayer.get_unique_id()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	mode = Mode.ONLINE_HOST
	local_player_id = 0
	peer_player_map[multiplayer.get_unique_id()] = 0
	return OK


## Connect to a host's room via the relay server using their room code.
func join_online(game_code: String) -> Error:
	_room_code = game_code
	var ws_peer := WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d/%s" % [RELAY_HOST, RELAY_PORT, game_code]
	var err := ws_peer.create_client(url)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = ws_peer

	# Wait for relay to assign our peer ID
	err = await _wait_for_ws_connection()
	if err != OK:
		multiplayer.multiplayer_peer = null
		return err

	# In relay mode, peer_connected fires when we learn about the host
	multiplayer.peer_connected.connect(_on_relay_client_peer_found)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	mode = Mode.ONLINE_CLIENT
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
	if multiplayer.peer_connected.is_connected(_on_relay_client_peer_found):
		multiplayer.peer_connected.disconnect(_on_relay_client_peer_found)

	mode = Mode.SOLO
	host_peer_id = 1
	local_player_id = -1
	peer_player_map.clear()
	opponent_connected = false
	version_verified = false
	_room_code = ""


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


## Waits for the WebSocket connection to be established (relay assigns peer ID).
## Returns OK on success, ERR_TIMEOUT on failure.
func _wait_for_ws_connection() -> Error:
	var connected := false
	var failed := false
	var on_connected := func(): connected = true
	var on_failed := func(): failed = true

	multiplayer.connected_to_server.connect(on_connected)
	multiplayer.connection_failed.connect(on_failed)

	var elapsed := 0.0
	while elapsed < WS_CONNECT_TIMEOUT and not connected and not failed:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	if multiplayer.connected_to_server.is_connected(on_connected):
		multiplayer.connected_to_server.disconnect(on_connected)
	if multiplayer.connection_failed.is_connected(on_failed):
		multiplayer.connection_failed.disconnect(on_failed)

	return OK if connected else ERR_TIMEOUT


# --- Host callbacks ---

func _on_peer_connected(peer_id: int) -> void:
	# Assign the connecting peer as player 1
	peer_player_map[peer_id] = 1
	peer_player_map[multiplayer.get_unique_id()] = 0
	opponent_connected = true
	_rpc_assign_player.rpc_id(peer_id, 1)
	_rpc_exchange_version.rpc_id(peer_id, GAME_VERSION)
	player_connected.emit(peer_id)
	_start_version_timeout()


func _on_peer_disconnected(peer_id: int) -> void:
	peer_player_map.erase(peer_id)
	opponent_connected = false
	player_disconnected.emit(peer_id)


# --- Client callbacks ---

## LAN client: connected directly to the host (server = peer 1).
func _on_connected_to_server() -> void:
	opponent_connected = true
	_rpc_exchange_version.rpc_id(host_peer_id, GAME_VERSION)
	player_connected.emit(host_peer_id)
	_start_version_timeout()


## Relay client: discovered the host via peer_connected signal.
func _on_relay_client_peer_found(peer_id: int) -> void:
	host_peer_id = peer_id
	opponent_connected = true
	_rpc_exchange_version.rpc_id(peer_id, GAME_VERSION)
	player_connected.emit(peer_id)
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


func _start_version_timeout() -> void:
	await get_tree().create_timer(VERSION_TIMEOUT).timeout
	if not version_verified and opponent_connected:
		version_mismatch.emit(GAME_VERSION, "unknown")
		disconnect_game()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_exchange_version(remote_version: String) -> void:
	if remote_version != GAME_VERSION:
		version_mismatch.emit(GAME_VERSION, remote_version)
		disconnect_game()
		return
	version_verified = true
