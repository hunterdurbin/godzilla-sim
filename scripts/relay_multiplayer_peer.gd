class_name RelayMultiplayerPeer
extends MultiplayerPeerExtension

## Custom MultiplayerPeer that connects two players via a WebSocket relay.
##
## Host gets unique_id = 1 (acts as server), client gets unique_id = 2.
## The relay transparently forwards binary frames between them.
## Text frames carry control messages: "J" = other peer joined, "L" = other peer left.

var _ws := WebSocketPeer.new()
var _unique_id: int = 0
var _is_host: bool = false
var _other_peer_id: int = 0
var _connection_status := CONNECTION_DISCONNECTED
var _other_connected: bool = false

var _target_peer: int = 0
var _transfer_mode := TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _refuse: bool = false

var _incoming: Array[PackedByteArray] = []


func connect_as_host(url: String) -> Error:
	_unique_id = 1
	_is_host = true
	_other_peer_id = 2
	_connection_status = CONNECTION_CONNECTING
	_ws.outbound_buffer_size = 1048576 # 1 MB — default 64 KB is too small for game state
	_ws.inbound_buffer_size = 1048576
	return _ws.connect_to_url(url)


func connect_as_client(url: String) -> Error:
	_unique_id = 2
	_is_host = false
	_other_peer_id = 1
	_connection_status = CONNECTION_CONNECTING
	_ws.outbound_buffer_size = 1048576
	_ws.inbound_buffer_size = 1048576
	return _ws.connect_to_url(url)


func _poll() -> void:
	_ws.poll()

	# Process all pending packets first (handles text "L" arriving just before close frame)
	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if _ws.was_string_packet():
			_handle_control(pkt.get_string_from_utf8())
		else:
			_incoming.append(pkt)

	var state := _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if _connection_status == CONNECTION_CONNECTING:
			if _is_host:
				# Host becomes CONNECTED as soon as WebSocket opens (waits for client via "J")
				_connection_status = CONNECTION_CONNECTED
			elif _other_connected:
				# Client waits for "J" before becoming CONNECTED so that
				# peer_connected(1) fires before SceneMultiplayer emits connected_to_server
				_connection_status = CONNECTION_CONNECTED

	elif state == WebSocketPeer.STATE_CLOSED:
		if _other_connected:
			_other_connected = false
			emit_signal("peer_disconnected", _other_peer_id)
		if _connection_status != CONNECTION_DISCONNECTED:
			_connection_status = CONNECTION_DISCONNECTED


func _handle_control(msg: String) -> void:
	match msg:
		"J":
			if not _other_connected:
				_other_connected = true
				# Must transition to CONNECTED before emitting peer_connected.
				# SceneMultiplayer's _admit_peer emits connected_to_server synchronously
				# during this signal, and rpcp() rejects RPCs unless status is CONNECTED.
				if _connection_status == CONNECTION_CONNECTING:
					_connection_status = CONNECTION_CONNECTED
				emit_signal("peer_connected", _other_peer_id)
		"L":
			if _other_connected:
				_other_connected = false
				emit_signal("peer_disconnected", _other_peer_id)


# --- PacketPeer ---

func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front()


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	return _ws.send(p_buffer, WebSocketPeer.WRITE_MODE_BINARY)


# --- MultiplayerPeer ---

func _set_target_peer(p_peer: int) -> void:
	_target_peer = p_peer


func _get_packet_peer() -> int:
	return _other_peer_id


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return TRANSFER_MODE_RELIABLE


func _get_unique_id() -> int:
	return _unique_id


func _is_server() -> bool:
	return _is_host


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _connection_status


func _get_max_packet_size() -> int:
	return 65536


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
	_ws.close()
	_connection_status = CONNECTION_DISCONNECTED
	_incoming.clear()
	_other_connected = false


func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	if p_peer == _other_peer_id:
		_ws.close()


func _is_server_relay_supported() -> bool:
	return true
