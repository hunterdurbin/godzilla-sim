class_name GameRoom
extends Node

## One match on the dedicated server: a SceneMultiplayer branch rooted at
## this node, a RoomVirtualPeer multiplexed over the shared WebSocket layer,
## and the production GameBoard/GameSession/MultiplayerSync chain (with
## HeadlessBoard standing in for the presentation scene). RPC node paths are
## encoded relative to the branch root, so the chain resolves identically on
## clients whose GameBoard sits at /root/GameBoard.

## Both seats disconnected or match over — ServerMain can GC the room.
signal emptied

## Seconds a disconnected player's seat is protected before the opponent may
## claim the win. The seat itself survives until room GC.
const GRACE_SECONDS: float = 90.0

## Per-room override (ServerMain sets this from --grace= for test runs).
var grace_seconds: float = GRACE_SECONDS

const HEADLESS_BOARD := preload("res://scripts/server/headless_board.gd")
const GAME_SESSION := preload("res://scripts/session/game_session.gd")
const MULTIPLAYER_SYNC := preload("res://scripts/session/multiplayer_sync.gd")
const EFFECT_UI_ROUTER := preload("res://scripts/session/effect_ui_router.gd")

var code: String = ""
var game_mode: String = ""
var is_public: bool = false
var conn_mgr: ServerConnectionManager
var virtual_peer: RoomVirtualPeer
var api: SceneMultiplayer
var board: HeadlessBoard
var match_started: bool = false
var match_over: bool = false

## conn_id -> player_id. Shared by reference with the room's NetContext so
## MultiplayerSync/EffectUIRouter always see the live seat map.
var peer_player_map: Dictionary = {}

## Per-player seat records (null = empty seat).
## {conn_id, name, token, deck: {monster_deck, main_deck}, deck_name,
##  decklist, connected, board_ready}
var seats: Array = [null, null]


## Must be called AFTER the room node is in the tree (branch registration
## needs a valid NodePath) and BEFORE any player is seated.
func setup(p_code: String, p_mode: String, p_conn_mgr: ServerConnectionManager) -> void:
	code = p_code
	game_mode = p_mode
	conn_mgr = p_conn_mgr

	api = SceneMultiplayer.new()
	virtual_peer = RoomVirtualPeer.new()
	virtual_peer.send_func = conn_mgr.send_binary
	api.multiplayer_peer = virtual_peer
	get_tree().set_multiplayer(api, get_path())

	var net_ctx := NetContext.for_room(peer_player_map)
	board = HEADLESS_BOARD.new()
	board.name = "GameBoard"
	board.room = self
	var session_node: GameSession = GAME_SESSION.new()
	session_node.name = "GameSession"
	var sync_node: MultiplayerSync = MULTIPLAYER_SYNC.new()
	sync_node.name = "MultiplayerSync"
	sync_node.net = net_ctx
	var router_node: EffectUIRouter = EFFECT_UI_ROUTER.new()
	router_node.name = "EffectUIRouter"
	router_node.net = net_ctx
	router_node.bind_all_prompts = true
	session_node.add_child(sync_node)
	session_node.add_child(router_node)
	board.add_child(session_node)
	add_child(board)


func teardown() -> void:
	get_tree().set_multiplayer(null, get_path())
	queue_free()


# --- Seat management ---

func has_space() -> bool:
	return seats[0] == null or seats[1] == null


## Seat a player; returns the seat record or {} when full.
func seat_player(conn_id: int, pname: String) -> Dictionary:
	for pid in range(2):
		if seats[pid] == null:
			var seat := {
				"conn_id": conn_id,
				"player_id": pid,
				"name": pname,
				"token": _generate_token(),
				"deck": {},
				"deck_name": "",
				"decklist": null,
				"connected": true,
				"disconnected_at_ms": 0,
				"board_ready": false,
				# False while the player is away in a lobby-bot game (BUSY/READY
				# control messages) — the match won't be announced until both
				# players are present in the lobby.
				"lobby_ready": true,
			}
			seats[pid] = seat
			peer_player_map[conn_id] = pid
			virtual_peer.seat_peer(conn_id)
			broadcast_lobby_state()
			return seat
	return {}


func player_for_peer(conn_id: int) -> int:
	return peer_player_map.get(conn_id, -1)


## Connection id of a player's seat, or -1 if empty/disconnected.
func peer_for_player(player_id: int) -> int:
	var seat = seats[player_id]
	if seat == null or not seat["connected"]:
		return -1
	return seat["conn_id"]


# --- Lobby flow ---

func set_deck(conn_id: int, payload: Dictionary) -> void:
	var pid := player_for_peer(conn_id)
	if pid < 0 or match_started:
		return
	var monster_entries: Array = payload.get("monster", [])
	var main_entries: Array = payload.get("main", [])
	var built := DecklistManager.build_deck_from_entries(pid, monster_entries, main_entries)
	seats[pid]["deck"] = built
	seats[pid]["deck_name"] = str(payload.get("deck_name", ""))
	seats[pid]["decklist"] = {
		"main_entries": main_entries,
		"monster_deck": built["monster_deck"],
	}
	broadcast_lobby_state()
	_maybe_announce_start()


func mark_board_ready(conn_id: int) -> void:
	var pid := player_for_peer(conn_id)
	if pid < 0:
		return
	seats[pid]["board_ready"] = true
	_maybe_start_match()


## Pre-match seat status for the lobby UI: who is here and whose deck is in.
## Sent to both connected seats whenever a seat or deck changes.
func broadcast_lobby_state() -> void:
	if match_started:
		return
	for pid in range(2):
		var conn_id := peer_for_player(pid)
		if conn_id <= 0:
			continue
		var opp = seats[1 - pid]
		conn_mgr.send_control(conn_id, {
			"type": "LOBBY",
			"you_deck_ready": not seats[pid]["deck"].is_empty(),
			"opponent_connected": opp != null and opp["connected"],
			"opponent_name": opp["name"] if opp != null else "",
			"opponent_deck_ready": opp != null and not opp["deck"].is_empty(),
		})


## Away/back from a lobby-bot game while waiting in this room.
func set_lobby_ready(conn_id: int, ready: bool) -> void:
	var pid := player_for_peer(conn_id)
	if pid < 0 or match_started:
		return
	seats[pid]["lobby_ready"] = ready
	if ready:
		_maybe_announce_start()


## Both decks in and both players present — tell the clients to load the
## game board.
func _maybe_announce_start() -> void:
	if match_started:
		return
	for pid in range(2):
		if seats[pid] == null or seats[pid]["deck"].is_empty() or not seats[pid]["lobby_ready"]:
			return
	for pid in range(2):
		conn_mgr.send_control(seats[pid]["conn_id"], {
			"type": "START",
			"player_id": pid,
			"mode": game_mode,
			"opponent_name": seats[1 - pid]["name"],
		})


## Both boards loaded — build the session and play.
func _maybe_start_match() -> void:
	if match_started:
		return
	for pid in range(2):
		if seats[pid] == null or seats[pid]["deck"].is_empty() or not seats[pid]["board_ready"]:
			return
	match_started = true

	var config := SessionConfig.new()
	config.game_mode = game_mode
	for pid in range(2):
		config.player_names[pid] = seats[pid]["name"]
		config.decks[pid] = seats[pid]["deck"]
		config.deck_names[pid] = seats[pid]["deck_name"]
		config.decklists[pid] = seats[pid]["decklist"]
	print("[Room %s] Starting match: %s vs %s" % [code, config.player_names[0], config.player_names[1]])
	board.start_match(config)


# --- Connection lifecycle ---

func handle_binary(conn_id: int, pkt: PackedByteArray) -> void:
	virtual_peer.push_packet(conn_id, pkt)


func on_connection_closed(conn_id: int) -> void:
	var pid := player_for_peer(conn_id)
	if pid < 0:
		return
	seats[pid]["connected"] = false
	seats[pid]["disconnected_at_ms"] = Time.get_ticks_msec()
	virtual_peer.unseat_peer(conn_id)
	peer_player_map.erase(conn_id)
	print("[Room %s] Player %d disconnected" % [code, pid])
	if not match_started:
		# Pre-match: free the seat entirely so someone else can take it.
		seats[pid] = null
		broadcast_lobby_state()
		if peer_for_player(0) < 0 and peer_for_player(1) < 0:
			emptied.emit()
	else:
		# Mid-match the seat is held for reconnect (room GC'd by ServerMain's
		# sweep if nobody returns); tell the survivor the grace clock started.
		var other_peer := peer_for_player(1 - pid)
		if other_peer > 0:
			conn_mgr.send_control(other_peer, {
				"type": "PEER_PRESENT",
				"player_id": pid,
				"connected": false,
				"grace_remaining_s": grace_seconds,
			})


## Re-seat a returning player by reconnect token. Returns the seat record or
## {} if the token matches no seat.
func reconnect_player(conn_id: int, token: String) -> Dictionary:
	for pid in range(2):
		var seat = seats[pid]
		if seat == null or seat["token"] != token:
			continue
		if seat["connected"]:
			# Old connection still lingering (e.g. died without FIN) — the new
			# one takes over the seat.
			var old_conn: int = seat["conn_id"]
			virtual_peer.unseat_peer(old_conn)
			peer_player_map.erase(old_conn)
			conn_mgr.close_connection(old_conn, 4003, "Replaced by reconnect")
		seat["conn_id"] = conn_id
		seat["connected"] = true
		seat["disconnected_at_ms"] = 0
		peer_player_map[conn_id] = pid
		virtual_peer.seat_peer(conn_id)
		print("[Room %s] Player %d reconnected" % [code, pid])
		var other_peer := peer_for_player(1 - pid)
		if other_peer > 0:
			conn_mgr.send_control(other_peer, {
				"type": "PEER_PRESENT",
				"player_id": pid,
				"connected": true,
			})
		return seat
	return {}


## True when the seated player at sender_conn may claim the win: the match is
## live, their opponent is disconnected, and the grace period has elapsed.
func can_claim_win(sender_conn: int) -> bool:
	if not match_started or match_over:
		return false
	var pid := player_for_peer(sender_conn)
	if pid < 0:
		return false
	var opp = seats[1 - pid]
	if opp == null or opp["connected"]:
		return false
	var down_ms: int = opp["disconnected_at_ms"]
	return down_ms > 0 and (Time.get_ticks_msec() - down_ms) / 1000.0 >= grace_seconds


## True when this room can be garbage-collected by the periodic sweep.
func is_abandoned(now_ms: int, mid_game_hold_s: float, post_game_hold_s: float) -> bool:
	if peer_for_player(0) > 0 or peer_for_player(1) > 0:
		return false
	var last_seen_ms := 0
	for seat in seats:
		if seat != null:
			last_seen_ms = maxi(last_seen_ms, int(seat["disconnected_at_ms"]))
	var hold_s := post_game_hold_s if match_over else mid_game_hold_s
	return (now_ms - last_seen_ms) / 1000.0 >= hold_s


func on_match_ended(winner_id: int, reason_key: String) -> void:
	match_over = true
	print("[Room %s] Match over: winner=%d reason=%s" % [code, winner_id, reason_key])
	# TODO(M2): stats upload, replay send, rematch support, room GC timing.


func _generate_token() -> String:
	var bytes := Crypto.new().generate_random_bytes(32)
	return bytes.hex_encode()
