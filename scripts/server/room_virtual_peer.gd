class_name RoomVirtualPeer
extends MultiplayerPeerExtension

## Per-room MultiplayerPeer for the dedicated server. The room's
## SceneMultiplayer branch sees this as "the server" (unique_id 1); the
## physical transport is the shared WebSocket layer owned by
## ServerConnectionManager, which pushes inbound binary frames in via
## push_packet() and receives outbound frames through send_func.
##
## Peer ids on this API are the process-unique connection ids assigned by the
## connection manager (always >= 2). seat_peer()/unseat_peer() drive
## peer_connected/peer_disconnected, which in turn drive MultiplayerSync's
## existing resync machinery.

## Callable(conn_id: int, bytes: PackedByteArray) — outbound transport.
var send_func: Callable = Callable()

var _seated: Dictionary = {} # conn_id -> true
var _incoming: Array = [] # of {sender: int, pkt: PackedByteArray}

var _target_peer: int = 0
var _transfer_mode := TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _refuse: bool = false


## Admit a (re)connected player's connection to this room's API.
func seat_peer(conn_id: int) -> void:
	if _seated.has(conn_id):
		return
	_seated[conn_id] = true
	emit_signal("peer_connected", conn_id)


## Remove a dropped player's connection from this room's API.
func unseat_peer(conn_id: int) -> void:
	if not _seated.has(conn_id):
		return
	_seated.erase(conn_id)
	emit_signal("peer_disconnected", conn_id)


func is_seated(conn_id: int) -> bool:
	return _seated.has(conn_id)


## Called by the connection manager for every inbound binary frame from a
## connection seated in this room.
func push_packet(sender_conn_id: int, pkt: PackedByteArray) -> void:
	if not _seated.has(sender_conn_id):
		push_warning("[RoomPeer] Dropping frame from unseated conn %d (%d bytes)" % [sender_conn_id, pkt.size()])
		return # Stale frame from an unseated connection — drop
	_incoming.append({"sender": sender_conn_id, "pkt": pkt})


func _send_to(conn_id: int, p_buffer: PackedByteArray) -> void:
	if send_func.is_valid():
		send_func.call(conn_id, p_buffer)


# --- PacketPeer ---

func _poll() -> void:
	pass # Transport is polled by ServerConnectionManager


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_peer() -> int:
	if _incoming.is_empty():
		return 0
	return _incoming[0]["sender"]


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front()["pkt"]


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _target_peer > 0:
		_send_to(_target_peer, p_buffer)
	else:
		# 0 = broadcast to all; negative = all except |target|
		var excluded := -_target_peer
		for conn_id in _seated:
			if conn_id != excluded:
				_send_to(conn_id, p_buffer)
	return OK


# --- MultiplayerPeer ---

func _set_target_peer(p_peer: int) -> void:
	_target_peer = p_peer


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return TRANSFER_MODE_RELIABLE


func _get_unique_id() -> int:
	return 1


func _is_server() -> bool:
	return true


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return CONNECTION_CONNECTED


func _get_max_packet_size() -> int:
	return 1048576


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _transfer_mode


func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void:
	_transfer_mode = p_mode


func _get_transfer_channel() -> int:
	return _transfer_channel


func _set_transfer_channel(p_channel: int) -> void:
	_transfer_channel = p_channel


func _is_refusing_new_connections() -> bool:
	return _refuse


func _set_refuse_new_connections(p_enable: bool) -> void:
	_refuse = p_enable


func _close() -> void:
	for conn_id in _seated.keys():
		emit_signal("peer_disconnected", conn_id)
	_seated.clear()
	_incoming.clear()


func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	# SceneMultiplayer calls this itself when a peer's RPC fails validation
	# (bad node path / method / args) — log it, it silently kills the seat.
	push_warning("[RoomPeer] _disconnect_peer(%d) called by the multiplayer API" % p_peer)
	unseat_peer(p_peer)


func _is_server_relay_supported() -> bool:
	return true
