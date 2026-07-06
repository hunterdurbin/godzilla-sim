class_name LobbyBotController
extends Node
## Public-lobby bot fallback: waiting banner, opponent found/disconnected dialogs, countdown + return-to-lobby flow.
## Method bodies moved verbatim from game_board.gd (Phase 8 split);
## remaining board state/methods are reached via `_board`. The board
## keeps one-line delegates, so call sites, signal connections, and the
## session-layer `_board.*` contract are unchanged.

var _board: GameBoard

var _lobby_banner: Control = null
var _lobby_banner_label: Label = null
var _lobby_banner_start_msec: int = 0
var _opponent_found_dialog: AcceptDialog = null
var _opponent_found_timer: Timer = null
var _opponent_found_remaining: int = 0
var _opponent_found_handled: bool = false


func _ready() -> void:
	_board = get_parent() as GameBoard


func _setup_lobby_bot_ui() -> void:
	_lobby_banner_start_msec = Time.get_ticks_msec()
	# Park the banner under the chat row inside the log panel so cards/board
	# elements never cover it.
	var log_vbox: VBoxContainer = _board.get_node("LogPanel/LogVBox")
	var hbox := HBoxContainer.new()
	hbox.name = "LobbyWaitingBanner"
	hbox.add_theme_constant_override("separation", 8)

	_lobby_banner_label = Label.new()
	_lobby_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lobby_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_banner_label.add_theme_font_size_override("font_size", 11)
	_lobby_banner_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3, 1))
	hbox.add_child(_lobby_banner_label)

	var return_btn := Button.new()
	return_btn.text = tr("STR_GB_RETURN_TO_LOBBY")
	return_btn.add_theme_font_size_override("font_size", 10)
	return_btn.pressed.connect(_board._on_lobby_banner_return_pressed)
	hbox.add_child(return_btn)

	log_vbox.add_child(hbox)
	_lobby_banner = hbox
	_board._update_lobby_banner_label()

	NetworkManager.player_connected.connect(_board._on_lobby_opponent_connected)
	NetworkManager.player_disconnected.connect(_board._on_lobby_opponent_disconnected)
	tree_exiting.connect(_board._disconnect_lobby_bot_signals)


func _disconnect_lobby_bot_signals() -> void:
	if NetworkManager.player_connected.is_connected(_board._on_lobby_opponent_connected):
		NetworkManager.player_connected.disconnect(_board._on_lobby_opponent_connected)
	if NetworkManager.player_disconnected.is_connected(_board._on_lobby_opponent_disconnected):
		NetworkManager.player_disconnected.disconnect(_board._on_lobby_opponent_disconnected)


func _on_lobby_opponent_disconnected(_peer_id: int) -> void:
	# Opponent gave up while we kept playing bot. Reset so a future joiner re-triggers the dialog.
	_opponent_found_handled = false
	_board._cleanup_opponent_found_dialog()


func _process_lobby_banner_tick() -> void:
	if _board._is_lobby_bot and is_instance_valid(_lobby_banner_label):
		_board._update_lobby_banner_label()


func _update_lobby_banner_label() -> void:
	var elapsed: int = int((Time.get_ticks_msec() - _lobby_banner_start_msec) / 1000.0)
	_lobby_banner_label.text = tr("STR_GB_LOBBY_WAITING_BANNER_FMT") % [int(elapsed / 60.0), elapsed % 60]


func _on_lobby_banner_return_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.exit_lobby_bot_game()
	NetworkManager.change_scene("res://scenes/lobby/PublicLobby.tscn")


func _on_lobby_opponent_connected(_peer_id: int) -> void:
	if not _board._is_lobby_bot or _opponent_found_handled:
		return
	_opponent_found_handled = true
	_board._show_opponent_found_dialog()


func _show_opponent_found_dialog() -> void:
	SfxManager.play("action_required")
	_opponent_found_dialog = AcceptDialog.new()
	_opponent_found_dialog.title = tr("STR_GB_OPPONENT_FOUND_TITLE")
	_opponent_found_dialog.dialog_text = tr("STR_GB_OPPONENT_FOUND_BODY")
	_opponent_found_dialog.get_ok_button().text = tr("STR_GB_OPPONENT_FOUND_START")
	_opponent_found_dialog.add_button(tr("STR_GB_OPPONENT_FOUND_KEEP_BOT"), false, "keep_bot")
	_opponent_found_dialog.confirmed.connect(_board._on_opponent_found_start)
	_opponent_found_dialog.custom_action.connect(_board._on_opponent_found_custom_action)
	_board.add_child(_opponent_found_dialog)
	GamepadHelper.register_modal(_opponent_found_dialog)
	_opponent_found_dialog.popup_centered()

	_opponent_found_remaining = 20
	_opponent_found_timer = Timer.new()
	_opponent_found_timer.wait_time = 1.0
	_opponent_found_timer.one_shot = false
	_opponent_found_timer.timeout.connect(_board._on_opponent_found_timer_tick)
	_board.add_child(_opponent_found_timer)
	_opponent_found_timer.start()
	_board._update_opponent_found_countdown()


func _on_opponent_found_timer_tick() -> void:
	_opponent_found_remaining -= 1
	if _opponent_found_remaining <= 0:
		_board._on_opponent_found_start()
		return
	_board._update_opponent_found_countdown()


func _update_opponent_found_countdown() -> void:
	if not is_instance_valid(_opponent_found_dialog):
		return
	_opponent_found_dialog.dialog_text = "%s\n\n%s" % [
		tr("STR_GB_OPPONENT_FOUND_BODY"),
		tr("STR_GB_OPPONENT_FOUND_AUTO_FMT") % _opponent_found_remaining,
	]


func _on_opponent_found_start() -> void:
	_board._cleanup_opponent_found_dialog()
	NetworkManager.exit_lobby_bot_game()
	NetworkManager.change_scene("res://scenes/lobby/PublicLobby.tscn")


func _on_opponent_found_custom_action(action: StringName) -> void:
	if action == "keep_bot":
		_board._cleanup_opponent_found_dialog()
		# Tell the joined client we're declining so they can drop and find another lobby
		# rather than sitting indefinitely on a "Waiting for game to start" screen.
		NetworkManager.notify_match_declined()


func _cleanup_opponent_found_dialog() -> void:
	if is_instance_valid(_opponent_found_timer):
		_opponent_found_timer.stop()
		_opponent_found_timer.queue_free()
		_opponent_found_timer = null
	if is_instance_valid(_opponent_found_dialog):
		_opponent_found_dialog.queue_free()
		_opponent_found_dialog = null


# --- In-flight action indicator (multiplayer client) ---
