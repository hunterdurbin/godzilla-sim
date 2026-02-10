extends Node

## Manages multiplayer connections using ENetMultiplayerPeer.
## Supports LAN (direct IP) and Online (via Noray relay/NAT punchthrough).
## Registered as an autoload singleton. Contains no game logic —
## just connection lifecycle, player assignment, and session state.

enum Mode { SOLO, HOST, CLIENT, ONLINE_HOST, ONLINE_CLIENT }

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal game_starting()

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 2
const NORAY_HOST: String = "tomfol.io"
const NORAY_PORT: int = 8890

var mode: Mode = Mode.SOLO
var local_player_id: int = -1
var peer_player_map: Dictionary = {}  # {peer_id: player_id}
var opponent_connected: bool = false
var noray_connected: bool = false


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
	peer_player_map[1] = 0  # Server's own peer ID is always 1
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


## Connect to the Noray relay server and join a host by their game code (OID).
## Returns OK on success.
func join_online(host_oid: String, host: String = NORAY_HOST, port: int = NORAY_PORT) -> Error:
	var err := await _connect_noray(host, port)
	if err != OK:
		return err

	# Listen for Noray connection signals
	Noray.on_connect_nat.connect(_on_noray_client_connect)
	Noray.on_connect_relay.connect(_on_noray_client_connect)

	# Try NAT punchthrough first
	err = Noray.connect_nat(host_oid)
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
		if Noray.on_connect_nat.is_connected(_on_noray_client_connect):
			Noray.on_connect_nat.disconnect(_on_noray_client_connect)
		if Noray.on_connect_relay.is_connected(_on_noray_client_connect):
			Noray.on_connect_relay.disconnect(_on_noray_client_connect)
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

func _connect_noray(host: String, port: int) -> Error:
	var err := await Noray.connect_to_host(host, port)
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


## Client-side: when Noray resolves the host's address, do UDP handshake then
## create ENet client.
func _on_noray_client_connect(address: String, port: int) -> void:
	var udp := PacketPeerUDP.new()
	udp.bind(Noray.local_port)
	udp.set_dest_address(address, port)

	var err := await PacketHandshake.over_packet_peer(udp)
	udp.close()

	if err != OK and err != ERR_BUSY:
		connection_failed.emit()
		return

	# Create ENet client using the Noray-assigned local port
	var peer := ENetMultiplayerPeer.new()
	err = peer.create_client(address, port, 0, 0, 0, Noray.local_port)
	if err != OK:
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
	player_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	peer_player_map.erase(peer_id)
	opponent_connected = false
	player_disconnected.emit(peer_id)


# --- Client callbacks ---

func _on_connected_to_server() -> void:
	opponent_connected = true
	player_connected.emit(1)  # Server peer ID


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
