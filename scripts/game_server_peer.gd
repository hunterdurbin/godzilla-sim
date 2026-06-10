class_name GameServerPeer
extends MultiplayerPeerExtension

## Client-side MultiplayerPeer for the dedicated game server (sibling of
## RelayMultiplayerPeer, which it will eventually replace for online play).
##
## One WebSocket to the server. Text frames carry the JSON control plane
## (HELLO/WELCOME/SEATED/START/...); binary frames are SceneMultiplayer RPC
## traffic passed through verbatim. The peer stays CONNECTING until the
## server's WELCOME assigns our unique id, then reports the server as peer 1.

signal control_received(msg: Dictionary)

var _ws := WebSocketPeer.new()
var _unique_id: int = 0
var _connection_status := CONNECTION_DISCONNECTED
var _hello: Dictionary = {}
var _hello_sent: bool = false

var _target_peer: int = 0
var _transfer_mode := TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _refuse: bool = false

var _incoming: Array[PackedByteArray] = []


func connect_to_server(url: String, player_name: String, version: String) -> Error:
	_hello = {"type": "HELLO", "version": version, "name": player_name}
	_hello_sent = false
	_connection_status = CONNECTION_CONNECTING
	_ws.outbound_buffer_size = 1048576 # 1 MB — default 64 KB is too small for game state
	_ws.inbound_buffer_size = 1048576
	return _ws.connect_to_url(url)


func send_control(msg: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


## Send a no-op text frame to keep the TCP path warm while idling in a lobby.
func send_keepalive() -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text("K")


func _poll() -> void:
	_ws.poll()

	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _hello_sent:
		_hello_sent = true
		_ws.send_text(JSON.stringify(_hello))

	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if _ws.was_string_packet():
			_handle_control(pkt.get_string_from_utf8())
		else:
			_incoming.append(pkt)

	if state == WebSocketPeer.STATE_CLOSED:
		if _connection_status != CONNECTION_DISCONNECTED:
			_connection_status = CONNECTION_DISCONNECTED
			emit_signal("peer_disconnected", 1)


func _handle_control(text: String) -> void:
	if text == "K":
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("[ServerPeer] Bad control frame: %s" % text.left(80))
		return
	var msg: Dictionary = parsed
	if str(msg.get("type", "")) == "WELCOME":
		_unique_id = int(msg.get("peer_id", 0))
		# Must transition to CONNECTED before emitting peer_connected:
		# SceneMultiplayer's _admit_peer emits connected_to_server synchronously
		# during this signal, and rpcp() rejects RPCs unless status is CONNECTED.
		_connection_status = CONNECTION_CONNECTED
		emit_signal("peer_connected", 1)
	control_received.emit(msg)


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
	var err := _ws.send(p_buffer, WebSocketPeer.WRITE_MODE_BINARY)
	if err != OK:
		push_warning("[ServerPeer] send failed: err=%d, size=%d" % [err, p_buffer.size()])
	return err


# --- MultiplayerPeer ---

func _set_target_peer(p_peer: int) -> void:
	_target_peer = p_peer


func _get_packet_peer() -> int:
	return 1 # Everything inbound is from (or relayed by) the server


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return TRANSFER_MODE_RELIABLE


func _get_unique_id() -> int:
	return _unique_id


func _is_server() -> bool:
	return false


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _connection_status


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
	_ws.close()
	_connection_status = CONNECTION_DISCONNECTED
	_incoming.clear()


func _disconnect_peer(_p_peer: int, _p_force: bool) -> void:
	_ws.close()


func _is_server_relay_supported() -> bool:
	return true
