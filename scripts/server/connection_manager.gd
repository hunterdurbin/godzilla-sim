class_name ServerConnectionManager
extends Node

## Physical transport layer for the dedicated server: one listening TCP port,
## one WebSocketPeer per client connection. Mirrors the framing contract of
## the relay (relay_multiplayer_peer.gd): text frames carry the JSON control
## plane, binary frames carry SceneMultiplayer RPC traffic.
##
## Owns no game or room state — ServerMain routes control messages and seats
## connections into rooms; rooms pull binary frames via binary_received.
##
## TODO(M2): answer plain HTTP GET on the same port ("/" status text,
## "/rooms" JSON) so the public lobby listing and the Discord status bot work
## against this server like they do against the relay.

signal control_received(conn_id: int, msg: Dictionary)
signal binary_received(conn_id: int, pkt: PackedByteArray)
signal connection_closed(conn_id: int)

const BUFFER_SIZE := 1048576 # 1 MB — default 64 KB is too small for game state

# Per-connection inbound rate limit (frames per rolling second). The RPC
# stream is reliable-ordered, so we must never drop individual frames — a
# silently dropped frame corrupts the protocol (an eaten action submit
# stalls the match invisibly). Floods get the connection CLOSED instead;
# an honest client reconnects through the normal token path. Burst traffic
# from dense turns measures ~30-60 frames/s, so the kick threshold sits
# well above legitimate play.
const KICK_FRAMES_PER_S := 300

# Clients heartbeat every 25s whenever connected; a connection silent for
# this long is dead or hostile (also reaps sockets that never sent HELLO).
const IDLE_TIMEOUT_MS := 75000

var _tcp := TCPServer.new()
var _next_conn_id: int = 2 # 1 is reserved for the server itself on room APIs
var _conns: Dictionary = {} # conn_id -> {ws: WebSocketPeer, open: bool, frames: int, window_ms: int}


func listen(port: int) -> Error:
	var err := _tcp.listen(port)
	if err != OK:
		push_error("[ConnMgr] Failed to listen on port %d: %d" % [port, err])
	else:
		print("[ConnMgr] Listening on port %d" % port)
	return err


func send_control(conn_id: int, msg: Dictionary) -> void:
	var conn: Dictionary = _conns.get(conn_id, {})
	if conn.is_empty():
		return
	var ws: WebSocketPeer = conn["ws"]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


func send_binary(conn_id: int, bytes: PackedByteArray) -> void:
	var conn: Dictionary = _conns.get(conn_id, {})
	if conn.is_empty():
		return
	var ws: WebSocketPeer = conn["ws"]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var err := ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)
		if err != OK:
			push_warning("[ConnMgr] send to %d failed: err=%d size=%d" % [conn_id, err, bytes.size()])


func close_connection(conn_id: int, code: int = 1000, reason: String = "") -> void:
	var conn: Dictionary = _conns.get(conn_id, {})
	if conn.is_empty():
		return
	conn["ws"].close(code, reason)


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		var ws := WebSocketPeer.new()
		ws.outbound_buffer_size = BUFFER_SIZE
		ws.inbound_buffer_size = BUFFER_SIZE
		var err := ws.accept_stream(stream)
		if err != OK:
			push_warning("[ConnMgr] accept_stream failed: %d" % err)
			continue
		var conn_id := _next_conn_id
		_next_conn_id += 1
		var now_ms := Time.get_ticks_msec()
		_conns[conn_id] = {"ws": ws, "open": false, "frames": 0, "window_ms": now_ms, "last_ms": now_ms}

	var closed: Array = []
	for conn_id in _conns:
		var conn: Dictionary = _conns[conn_id]
		var ws: WebSocketPeer = conn["ws"]
		ws.poll()

		var now := Time.get_ticks_msec()
		if now - conn["window_ms"] >= 1000:
			conn["window_ms"] = now
			conn["frames"] = 0

		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			conn["last_ms"] = now
			conn["frames"] += 1
			if conn["frames"] > KICK_FRAMES_PER_S:
				push_warning("[ConnMgr] Connection %d flooding (%d frames/s) — closing" % [conn_id, conn["frames"]])
				ws.close(4008, "Rate limit")
				break
			if ws.was_string_packet():
				var text := pkt.get_string_from_utf8()
				if text == "K":
					continue # idle keepalive
				var parsed: Variant = JSON.parse_string(text)
				if parsed is Dictionary:
					control_received.emit(conn_id, parsed)
				else:
					push_warning("[ConnMgr] Bad control frame from %d: %s" % [conn_id, text.left(80)])
			else:
				binary_received.emit(conn_id, pkt)

		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if not conn["open"]:
					conn["open"] = true
					print("[ConnMgr] Connection %d open" % conn_id)
				elif now - conn["last_ms"] > IDLE_TIMEOUT_MS:
					print("[ConnMgr] Connection %d idle %.0fs — closing" % [conn_id, (now - conn["last_ms"]) / 1000.0])
					ws.close(4009, "Idle timeout")
			WebSocketPeer.STATE_CLOSED:
				closed.append(conn_id)
			_:
				pass # CONNECTING / CLOSING — keep polling

	for conn_id in closed:
		var was_open: bool = _conns[conn_id]["open"]
		_conns.erase(conn_id)
		print("[ConnMgr] Connection %d closed" % conn_id)
		if was_open:
			connection_closed.emit(conn_id)
