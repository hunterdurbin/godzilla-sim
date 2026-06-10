extends Control

## Private online lobby — runs against the dedicated game server.
##
## Flow is symmetric (neither player is "the host" of the game session):
## one player creates a room and shares the code, the other joins with it,
## both submit a deck, and the SERVER starts the match once both decks are
## in (the scene change is driven by NetworkManager on the START message —
## there is no start button).

@onready var host_button: Button = $CenterContainer/VBoxContainer/HostPanel/HostButton
@onready var code_label: Label = $CenterContainer/VBoxContainer/HostPanel/CodeLabel
@onready var copy_button: Button = $CenterContainer/VBoxContainer/HostPanel/CopyButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinPanel/JoinButton
@onready var code_edit: LineEdit = $CenterContainer/VBoxContainer/JoinPanel/CodeEdit
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var deck_select: VBoxContainer = $CenterContainer/VBoxContainer/DeckSelect
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

var _seated: bool = false
var _deck_sent: bool = false
var _version_mismatch_shown: bool = false


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	back_button.pressed.connect(_on_back_pressed)
	deck_select.deck_selected.connect(_on_deck_selected)

	NetworkManager.server_room_created.connect(_on_room_created)
	NetworkManager.server_seated.connect(_on_seated)
	NetworkManager.server_lobby_update.connect(_on_lobby_update)
	NetworkManager.server_error.connect(_on_server_error)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.version_mismatch.connect(_on_version_mismatch)

	DecklistManager.clear_selections()

	# Match start is server-driven; there is no host-side start button.
	start_button.visible = false
	copy_button.visible = false
	code_label.text = ""
	status_label.text = ""


func _on_host_pressed() -> void:
	SfxManager.play("ui_click")
	if not await _ensure_connected():
		return
	NetworkManager.create_room(false, "")


func _on_join_pressed() -> void:
	SfxManager.play("ui_click")
	var code := code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = tr("STR_ONLINE_ENTER_CODE")
		return
	if not await _ensure_connected():
		return
	NetworkManager.join_room(code)


## Connect the control-plane bridge (idempotent). Returns false on failure
## with the UI restored.
func _ensure_connected() -> bool:
	if NetworkManager.mode == NetworkManager.Mode.ONLINE and NetworkManager.server_peer != null:
		return true
	_set_buttons_locked(true)
	status_label.text = tr("STR_ONLINE_CONNECTING_RELAY")
	var err := await NetworkManager.connect_to_server()
	if err != OK:
		if not _version_mismatch_shown:
			status_label.text = tr("STR_ONLINE_RELAY_FAILED_FMT") % err
		_set_buttons_locked(false)
		return false
	return true


func _on_room_created(code: String) -> void:
	code_label.text = code
	copy_button.visible = true
	status_label.text = tr("STR_ONLINE_SHARE_CODE")


func _on_seated(_room: String, _player_id: int) -> void:
	_seated = true
	if not deck_select.current_selection.is_empty():
		_send_deck(deck_select.current_selection)
	elif not copy_button.visible:
		# Joiner without a deck picked yet
		status_label.text = tr("STR_LAN_CONNECTED_SELECT_DECK")


func _on_deck_selected(deck_name: String) -> void:
	if deck_name.is_empty() or not _seated:
		return
	_send_deck(deck_name)


func _send_deck(deck_name: String) -> void:
	if NetworkManager.send_deck_to_server(deck_name):
		_deck_sent = true
		status_label.text = tr("STR_LAN_DECK_SENT_FMT") % deck_name


func _on_lobby_update(info: Dictionary) -> void:
	if not bool(info.get("opponent_connected", false)):
		if _seated:
			status_label.text = tr("STR_LAN_OPPONENT_DISCONNECTED") if _deck_sent else tr("STR_ONLINE_SHARE_CODE")
		return
	if bool(info.get("you_deck_ready", false)):
		if bool(info.get("opponent_deck_ready", false)):
			status_label.text = tr("STR_LAN_OPPONENT_DECK_READY")
		else:
			status_label.text = tr("STR_ONLINE_WAITING_OPPONENT_DECK")
	else:
		status_label.text = tr("STR_LAN_CONNECTED_SELECT_DECK")


func _on_server_error(code: String) -> void:
	match code:
		"not_found":
			status_label.text = tr("STR_ONLINE_ROOM_NOT_FOUND")
			_set_buttons_locked(false)
		"full":
			status_label.text = tr("STR_ONLINE_ROOM_FULL")
			_set_buttons_locked(false)
		"version":
			pass # version_mismatch handler shows the message
		_:
			status_label.text = tr("STR_ONLINE_CONNECTION_FAILED_RETRY")
			_set_buttons_locked(false)


func _on_connection_failed() -> void:
	status_label.text = tr("STR_ONLINE_CONNECTION_FAILED_RETRY")
	_set_buttons_locked(false)


func _on_version_mismatch(local_version: String, remote_version: String) -> void:
	_version_mismatch_shown = true
	status_label.text = tr("STR_LAN_VERSION_MISMATCH_FMT") % [local_version, remote_version]
	_set_buttons_locked(false)


func _set_buttons_locked(locked: bool) -> void:
	host_button.disabled = locked
	join_button.disabled = locked
	code_edit.editable = not locked


func _on_copy_pressed() -> void:
	SfxManager.play("ui_click")
	DisplayServer.clipboard_set(code_label.text)
	copy_button.text = tr("STR_COMMON_COPIED")
	await get_tree().create_timer(1.5).timeout
	copy_button.text = tr("STR_COMMON_COPY")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_back_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.disconnect_game()
	NetworkManager.change_scene("res://scenes/ui/OnlinePlay.tscn")
