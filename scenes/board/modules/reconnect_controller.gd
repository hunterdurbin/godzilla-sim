class_name ReconnectController
extends Node

## Disconnect/reconnect concern for multiplayer games: the blocking overlay,
## the claim-win countdown, the reconnect retry loop, and the resync handoff
## once the peer returns.
##
## Three flavors:
## - LAN: disconnect ends the game immediately.
## - Relay (legacy): host shows claim-win countdown; client retries the relay.
## - Dedicated server (Mode.ONLINE): symmetric. Your own drop runs the
##   reconnect loop (token re-seat + resync); your opponent's drop arrives as
##   a PEER_PRESENT message with the server's grace window, and claim-win is
##   an RPC the server validates.
##
## setup() is called from game_board._ready (multiplayer only). The board's
## _process delegates the per-frame timer update via process_tick() and uses
## is_overlay_active() to skip drag handling while the overlay blocks input.

const CLAIM_WIN_SECONDS: float = 10.0

var _board: Node
var _session: GameSession

# Dedicated server: when the opponent's grace period ends (survivor side).
var _grace_deadline_ms: int = 0

var waiting_for_reconnect: bool = false
var attempting: bool = false # Guard for client reconnect loop
var cumulative_seconds: float = 0.0 # Cumulative across all disconnects
var _current_start_ms: int = 0

# Overlay nodes (built in code)
var overlay: ColorRect = null
var _label: Label = null
var _timer_label: Label = null
var _claim_btn: Button = null
var _menu_btn: Button = null


func _ready() -> void:
	_board = get_parent()
	_session = _board.get_node_or_null("GameSession")


## Build the overlay and listen for peer disconnect/reconnect. Multiplayer only.
func setup() -> void:
	_build_overlay()
	NetworkManager.player_disconnected.connect(_on_opponent_disconnected)
	NetworkManager.player_reconnected.connect(_on_opponent_reconnected)
	if NetworkManager.mode == NetworkManager.Mode.ONLINE:
		NetworkManager.server_peer_present.connect(_on_peer_present)


func is_overlay_active() -> bool:
	return waiting_for_reconnect and overlay and overlay.visible


func hide_overlay() -> void:
	waiting_for_reconnect = false
	attempting = false
	if overlay:
		overlay.visible = false


## Per-frame countdown/elapsed label update while the overlay is showing.
func process_tick() -> void:
	if not is_overlay_active():
		return
	var elapsed_ms := Time.get_ticks_msec() - _current_start_ms
	var total_seconds := cumulative_seconds + elapsed_ms / 1000.0
	if _grace_deadline_ms > 0:
		# Dedicated server, survivor side: countdown from the server's grace
		# window until "Claim Win" becomes available.
		var remaining := (_grace_deadline_ms - Time.get_ticks_msec()) / 1000.0
		if remaining > 0:
			_timer_label.text = tr("STR_GB_CLAIM_WIN_TIMER_FMT").replace("{N}", str(ceili(remaining)))
		else:
			_timer_label.text = ""
			if not _claim_btn.visible:
				_claim_btn.visible = true
	elif NetworkManager.is_host():
		# Relay host: show countdown until "Claim Win" becomes available
		var remaining := CLAIM_WIN_SECONDS - total_seconds
		if remaining > 0:
			_timer_label.text = tr("STR_GB_CLAIM_WIN_TIMER_FMT").replace("{N}", str(ceili(remaining)))
		else:
			_timer_label.text = ""
			if not _claim_btn.visible:
				_claim_btn.visible = true
	else:
		# Reconnecting side: show elapsed time
		_timer_label.text = tr("STR_GB_RECONNECTING_FMT").replace("{N}", str(int(total_seconds)))


func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 200
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_label)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 20)
	_timer_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_timer_label)

	_claim_btn = Button.new()
	_claim_btn.text = tr("STR_GB_CLAIM_WIN")
	_claim_btn.custom_minimum_size = Vector2(200, 45)
	_claim_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_claim_btn.add_theme_font_size_override("font_size", 20)
	_claim_btn.visible = false
	_claim_btn.pressed.connect(_on_claim_win)
	vbox.add_child(_claim_btn)

	_menu_btn = Button.new()
	_menu_btn.text = tr("STR_GB_RETURN_TO_MENU")
	_menu_btn.custom_minimum_size = Vector2(200, 45)
	_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_btn.add_theme_font_size_override("font_size", 20)
	_menu_btn.pressed.connect(_board._on_main_menu_pressed)
	vbox.add_child(_menu_btn)

	overlay.add_child(vbox)
	_board.add_child(overlay)


func _on_opponent_disconnected(_peer_id: int) -> void:
	_board._disable_all_buttons()
	# If the game was already over (normal end), just hide the rematch button
	if _board.end_game_panel.visible:
		_board.btn_rematch.visible = false
		_board._rematch_deck_select.visible = false
		return

	# Dedicated server: player_disconnected here means OUR link to the server
	# dropped (the opponent's drop arrives as PEER_PRESENT instead) — run the
	# token reconnect loop.
	if NetworkManager.mode == NetworkManager.Mode.ONLINE:
		_board._on_log_message(GameLog.connection_lost_reconnecting())
		waiting_for_reconnect = true
		_current_start_ms = Time.get_ticks_msec()
		_grace_deadline_ms = 0
		_label.text = tr("STR_GB_CONNECTION_LOST_RECONNECTING")
		_timer_label.text = ""
		_claim_btn.visible = false
		_menu_btn.visible = true
		overlay.visible = true
		if not attempting:
			_attempt_server_reconnect()
		return

	var is_online: bool = NetworkManager.mode in [NetworkManager.Mode.ONLINE_HOST, NetworkManager.Mode.ONLINE_CLIENT]

	# LAN games: immediate disconnect (no reconnect possible)
	if not is_online:
		_handle_final_disconnect()
		return

	# Online HOST side: show overlay and wait for reconnect
	if NetworkManager.is_host():
		_board._on_log_message(GameLog.opponent_disconnected_waiting())
		waiting_for_reconnect = true
		_current_start_ms = Time.get_ticks_msec()
		_label.text = tr("STR_GB_OPPONENT_DISCONNECTED_WAIT")
		_timer_label.text = tr("STR_GB_CLAIM_WIN_TIMER_FMT").replace("{N}", str(int(CLAIM_WIN_SECONDS)))
		_claim_btn.visible = false
		overlay.visible = true
		return

	# Online CLIENT side: attempt to reconnect to the host via relay
	_board._on_log_message(GameLog.connection_lost_reconnecting())
	waiting_for_reconnect = true
	_current_start_ms = Time.get_ticks_msec()
	_label.text = tr("STR_GB_CONNECTION_LOST_RECONNECTING")
	_timer_label.text = ""
	_claim_btn.visible = false
	_menu_btn.visible = true
	overlay.visible = true
	if not attempting:
		_attempt_client_reconnect()


func _handle_final_disconnect() -> void:
	_board._game_ended_by_disconnect = true
	_board.end_game_panel.visible = true
	var win_label: Label = _board.end_game_panel.get_node_or_null("VBox/WinLabel")
	if win_label:
		win_label.text = tr("STR_GB_OPPONENT_DISCONNECTED")
	_board.btn_rematch.visible = false
	_board._upload_stats(_board.local_player_id, "Opponent disconnected", true)


func _attempt_client_reconnect() -> void:
	attempting = true
	var room_code := NetworkManager.get_game_code()
	while waiting_for_reconnect and is_inside_tree():
		_label.text = tr("STR_GB_CONNECTION_LOST_RECONNECTING")
		var err: Error = await NetworkManager.attempt_reconnect(room_code)
		if err == OK:
			# Reconnected — clear overlay and reset ALL client delta state
			cumulative_seconds += (Time.get_ticks_msec() - _current_start_ms) / 1000.0
			waiting_for_reconnect = false
			attempting = false
			overlay.visible = false
			# Reset delta state so next broadcast is treated as full state
			_board._sync.reset_client_stream()
			_board._action_pending = false
			_board._on_log_message(GameLog.reconnected())
			# Wait a frame for the connection to stabilize before sending RPCs
			await get_tree().process_frame
			if not is_inside_tree():
				return
			# Re-send player name and request full state resync from host.
			# The host already tried to resync during the relay handshake,
			# but those RPCs may have arrived before the connection was fully ready.
			RpcLogger.log_send("send_player_name", GameSettings.player_name.length())
			_board._sync._rpc_send_player_name.rpc_id(NetworkManager.host_peer_id, GameSettings.player_name)
			RpcLogger.log_send("request_resync", 0)
			_board._sync._rpc_request_resync.rpc_id(NetworkManager.host_peer_id)
			return
		# Failed — wait 2s and retry
		_label.text = tr("STR_GB_CONNECTION_LOST_RETRYING")
		await get_tree().create_timer(2.0).timeout
	attempting = false


## Dedicated server: reconnect with the seat token, then pull a fresh full
## state through the normal resync path.
func _attempt_server_reconnect() -> void:
	attempting = true
	while waiting_for_reconnect and is_inside_tree():
		_label.text = tr("STR_GB_CONNECTION_LOST_RECONNECTING")
		var err: Error = await NetworkManager.reconnect_to_server()
		if err == OK:
			cumulative_seconds += (Time.get_ticks_msec() - _current_start_ms) / 1000.0
			waiting_for_reconnect = false
			attempting = false
			overlay.visible = false
			_board._sync.reset_client_stream()
			_board._action_pending = false
			_board._on_log_message(GameLog.reconnected())
			await get_tree().process_frame
			if not is_inside_tree():
				return
			RpcLogger.log_send("request_resync", 0)
			_board._sync._rpc_request_resync.rpc_id(NetworkManager.host_peer_id)
			return
		if not waiting_for_reconnect or not is_inside_tree():
			break
		_label.text = tr("STR_GB_CONNECTION_LOST_RETRYING")
		await get_tree().create_timer(2.0).timeout
	attempting = false


## Dedicated server: the opponent dropped or returned (our own link is fine).
func _on_peer_present(player_id: int, connected: bool, grace_s: float) -> void:
	if player_id == _board.local_player_id:
		return
	if connected:
		if not waiting_for_reconnect:
			return
		cumulative_seconds += (Time.get_ticks_msec() - _current_start_ms) / 1000.0
		waiting_for_reconnect = false
		_grace_deadline_ms = 0
		overlay.visible = false
		_board._on_log_message(GameLog.opponent_reconnected())
		return
	_board._disable_all_buttons()
	if _board.end_game_panel.visible:
		_board.btn_rematch.visible = false
		_board._rematch_deck_select.visible = false
		return
	_board._on_log_message(GameLog.opponent_disconnected_waiting())
	waiting_for_reconnect = true
	_current_start_ms = Time.get_ticks_msec()
	_grace_deadline_ms = Time.get_ticks_msec() + int(grace_s * 1000.0)
	_label.text = tr("STR_GB_OPPONENT_DISCONNECTED_WAIT")
	_timer_label.text = tr("STR_GB_CLAIM_WIN_TIMER_FMT").replace("{N}", str(int(grace_s)))
	_claim_btn.visible = false
	_menu_btn.visible = true
	overlay.visible = true


func _on_opponent_reconnected(_peer_id: int) -> void:
	if not waiting_for_reconnect:
		return

	# Accumulate elapsed wait time
	cumulative_seconds += (Time.get_ticks_msec() - _current_start_ms) / 1000.0
	waiting_for_reconnect = false
	overlay.visible = false

	if not _board.end_game_panel.visible:
		# Game is still in progress — resync the client after a brief delay
		# to let the connection stabilize before sending large state RPCs
		_board._on_log_message(GameLog.opponent_reconnected())
		await get_tree().create_timer(0.2).timeout
		if not is_inside_tree():
			return
		_board._sync.resync_client(_get_client_peer_id())
	else:
		# Game ended while they were gone (win was claimed) — re-send result
		await get_tree().create_timer(0.2).timeout
		if not is_inside_tree():
			return
		RpcLogger.log_send("receive_game_ended", 4 + len("STR_LOG_REASON_OPPONENT_DISCONNECTED"))
		_board._sync._rpc_receive_game_ended.rpc(_board.local_player_id, "STR_LOG_REASON_OPPONENT_DISCONNECTED")
		# Show rematch button now that opponent is back
		_board.btn_rematch.visible = true
		_board.btn_rematch.disabled = false
		_board.btn_rematch.text = tr("STR_GB_REMATCH")
		_board._game_ended_by_disconnect = false
		_board._populate_rematch_deck_select()


func _get_client_peer_id() -> int:
	for peer_id in NetworkManager.peer_player_map:
		if peer_id != 1 and NetworkManager.peer_player_map[peer_id] != _board.local_player_id:
			return peer_id
	return -1


func _on_claim_win() -> void:
	if NetworkManager.mode == NetworkManager.Mode.ONLINE:
		# Dedicated server validates grace and ends the game; the result
		# arrives via the normal game-ended RPC.
		waiting_for_reconnect = false
		_grace_deadline_ms = 0
		overlay.visible = false
		RpcLogger.log_send("claim_win", 0)
		_board._sync._rpc_claim_win.rpc_id(NetworkManager.host_peer_id)
		return
	waiting_for_reconnect = false
	overlay.visible = false
	# End the game with local player as winner
	_board._game_ended_by_disconnect = true
	_board.end_game_panel.visible = true
	var win_label: Label = _board.end_game_panel.get_node_or_null("VBox/WinLabel")
	if win_label:
		win_label.text = tr("STR_GB_YOU_WIN_OPP_DISC")
	_board.btn_rematch.visible = false
	_board._disable_all_buttons()
	_board._upload_stats(_board.local_player_id, "Opponent disconnected", true)
	_board._on_log_message(GameLog.claimed_win_disconnect())
