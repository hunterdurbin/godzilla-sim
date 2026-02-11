extends Node

## Manages multiplayer connections using ENetMultiplayerPeer.
## Supports LAN (direct IP) and Online (via Noray relay/NAT punchthrough).
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
const NORAY_HOST: String = "godzillatcg.com"
const NORAY_PORT: int = 8890

var mode: Mode = Mode.SOLO
var local_player_id: int = -1
var peer_player_map: Dictionary = {} # {peer_id: player_id}
var opponent_connected: bool = false
var version_verified: bool = false
var noray_connected: bool = false
var _noray_host_oid: String = ""
var _noray_nat_attempted: bool = false
var _noray_connecting: bool = false


func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	mode = Mode.HOST
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
	return OK


## Connect to the Noray relay server and register as a host.
## Returns OK on success. On success, Noray.oid contains the game code to share.
func host_online(host: String = NORAY_HOST, port: int = NORAY_PORT) -> Error:
	var err := await _connect_noray(host, port)
	if err != OK:
		return err

	# Create ENet server on the port Noray assigned
	var peer := ENetMultiplayerPeer.new()
	err = peer.create_server(Noray.local_port, MAX_PLAYERS - 1)
	if err != OK:
		Noray.disconnect_from_host()
		noray_connected = false
		return err

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Listen for incoming Noray connections (both NAT and relay)
	Noray.on_connect_nat.connect(_on_noray_host_connect)
	Noray.on_connect_relay.connect(_on_noray_host_connect)

	mode = Mode.ONLINE_HOST
	local_player_id = 0
	peer_player_map[1] = 0
	return OK


## Connect to a host by their game code (OID) via the Noray relay server.
## The client skips register_host/register_remote to avoid conflicting with
## the host's registration (which causes disconnects on same-network NAT).
## Goes straight to relay instead of attempting NAT punchthrough.
func join_online(host_oid: String, host: String = NORAY_HOST, port: int = NORAY_PORT) -> Error:
	var resolved := _resolve_hostname(host)
	if resolved == "":
		return ERR_CANT_RESOLVE

	var err := await Noray.connect_to_host(resolved, port)
	if err != OK:
		return err

	noray_connected = true
	_noray_host_oid = host_oid
	_noray_connecting = false

	Noray.on_connect_relay.connect(_on_noray_client_relay)

	err = Noray.connect_relay(host_oid)
	if err != OK:
		Noray.disconnect_from_host()
		noray_connected = false
		return err

	mode = Mode.ONLINE_CLIENT
	return OK


func disconnect_game() -> void:
	# Clean up Noray connection
	if noray_connected:
		if Noray.on_connect_nat.is_connected(_on_noray_host_connect):
			Noray.on_connect_nat.disconnect(_on_noray_host_connect)
		if Noray.on_connect_relay.is_connected(_on_noray_host_connect):
			Noray.on_connect_relay.disconnect(_on_noray_host_connect)
		if Noray.on_connect_nat.is_connected(_on_noray_client_nat):
			Noray.on_connect_nat.disconnect(_on_noray_client_nat)
		if Noray.on_connect_relay.is_connected(_on_noray_client_relay):
			Noray.on_connect_relay.disconnect(_on_noray_client_relay)
		Noray.disconnect_from_host()
		noray_connected = false

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
	local_player_id = -1
	peer_player_map.clear()
	opponent_connected = false
	version_verified = false


func is_multiplayer() -> bool:
	return mode != Mode.SOLO


func is_host() -> bool:
	return mode == Mode.HOST or mode == Mode.ONLINE_HOST


func is_local_player_turn(current_player_id: int) -> bool:
	if mode == Mode.SOLO:
		return true
	return current_player_id == local_player_id


func get_local_player_id() -> int:
	return local_player_id


func start_lan_game() -> void:
	game_starting.emit()
	_rpc_start_game.rpc()
	get_tree().change_scene_to_file("res://scenes/board/GameBoard.tscn")


# --- Noray helpers ---

func _resolve_hostname(host: String) -> String:
	# Try Godot's built-in resolver first
	var resolved := IP.resolve_hostname(host, IP.TYPE_IPV4)
	if resolved != "":
		return resolved
	# Fallback: use system dig command (Godot's resolver fails on some macOS configs)
	var output: Array = []
	var exit_code := OS.execute("dig", ["+short", host, "A"], output)
	if exit_code == OK and output.size() > 0:
		var lines: String = output[0].strip_edges()
		if lines != "":
			return lines.split("\n")[0].strip_edges()
	return ""


func _connect_noray(host: String, port: int) -> Error:
	var resolved: String = _resolve_hostname(host)
	if resolved == "":
		return ERR_CANT_RESOLVE
	var err := await Noray.connect_to_host(resolved, port)
	if err != OK:
		return err

	Noray.register_host()
	await Noray.on_pid

	err = await Noray.register_remote()
	if err != OK:
		Noray.disconnect_from_host()
		return err

	noray_connected = true
	return OK


## Host-side: when a player connects via Noray, perform the ENet handshake.
func _on_noray_host_connect(address: String, port: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null:
		return
	await PacketHandshake.over_enet_peer(peer, address, port)


## Client-side NAT: handshake with peer, fall back to relay on failure.
func _on_noray_client_nat(address: String, port: int) -> void:
	if _noray_connecting or _noray_nat_attempted:
		return
	_noray_connecting = true
	_noray_nat_attempted = true

	var udp := PacketPeerUDP.new()
	udp.bind(Noray.local_port)
	udp.set_dest_address(address, port)

	var err := await PacketHandshake.over_packet_peer(udp)
	udp.close()

	if err != OK and err != ERR_BUSY:
		_noray_connecting = false
		Noray.connect_relay(_noray_host_oid)
		return

	_create_client_peer(address, port)


## Client-side relay: connect through the Noray relay server.
func _on_noray_client_relay(address: String, port: int) -> void:
	if _noray_connecting:
		return
	_noray_connecting = true
	_create_client_peer(address, port)


func _create_client_peer(address: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var local_port := Noray.local_port if Noray.local_port > 0 else 0
	var err := peer.create_client(address, port, 0, 0, 0, local_port)
	if err != OK:
		_noray_connecting = false
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Host callbacks ---

func _on_peer_connected(peer_id: int) -> void:
	# Assign the connecting peer as player 1
	peer_player_map[peer_id] = 1
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

func _on_connected_to_server() -> void:
	opponent_connected = true
	_rpc_exchange_version.rpc_id(1, GAME_VERSION)
	player_connected.emit(1) # Server peer ID
	_start_version_timeout()


func _on_connection_failed() -> void:
	disconnect_game()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	opponent_connected = false
	player_disconnected.emit(1)


# --- RPCs ---

@rpc("authority", "call_remote", "reliable")
func _rpc_assign_player(pid: int) -> void:
	# Client receives its player ID from the host
	local_player_id = pid


@rpc("authority", "call_remote", "reliable")
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
