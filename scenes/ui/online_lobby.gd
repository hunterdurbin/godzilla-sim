extends Control

## Private online lobby. Two backends, branched on
## NetworkManager.USE_DEDICATED_SERVER:
##
## Relay (default): host-client over the WebSocket relay — the host creates
## a room code, the client joins and sends its deck to the host, and the
## HOST presses Start.
##
## Dedicated server: symmetric — one player creates a room and shares the
## code, the other joins, both submit a deck, and the SERVER starts the
## match (scene change driven by NetworkManager on START; no start button).

@onready var host_button: Button = $CenterContainer/VBoxContainer/HostPanel/HostButton
@onready var code_label: Label = $CenterContainer/VBoxContainer/HostPanel/CodeLabel
@onready var copy_button: Button = $CenterContainer/VBoxContainer/HostPanel/CopyButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinPanel/JoinButton
@onready var code_edit: LineEdit = $CenterContainer/VBoxContainer/JoinPanel/CodeEdit
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var deck_select: VBoxContainer = $CenterContainer/VBoxContainer/DeckSelect
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

# Relay-mode state
var _host_deck_ready: bool = false
var _client_deck_received: bool = false
var _client_deck_name: String = ""
# Dedicated-server state
var _seated: bool = false
var _deck_sent: bool = false

var _version_mismatch_shown: bool = false


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	deck_select.deck_selected.connect(_on_deck_selected)

	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.version_mismatch.connect(_on_version_mismatch)
	if NetworkManager.USE_DEDICATED_SERVER:
		NetworkManager.server_room_created.connect(_on_room_created)
		NetworkManager.server_seated.connect(_on_seated)
		NetworkManager.server_lobby_update.connect(_on_lobby_update)
		NetworkManager.server_error.connect(_on_server_error)
	else:
		NetworkManager.player_connected.connect(_on_player_connected)
		NetworkManager.player_disconnected.connect(_on_player_disconnected)
		NetworkManager.version_verified_ok.connect(_update_start_button)

	DecklistManager.clear_selections()

	start_button.visible = false
	copy_button.visible = false
	code_label.text = ""
	status_label.text = ""


func _on_host_pressed() -> void:
	SfxManager.play("ui_click")
	if NetworkManager.USE_DEDICATED_SERVER:
		if not await _ensure_connected():
			return
		NetworkManager.create_room(false, "")
		return

	_set_buttons_locked(true)
	status_label.text = tr("STR_ONLINE_CONNECTING_RELAY")

	var err := await NetworkManager.host_online()
	if err != OK:
		status_label.text = tr("STR_ONLINE_RELAY_FAILED_FMT") % err
		_set_buttons_locked(false)
		return

	code_label.text = NetworkManager.get_game_code()
	copy_button.visible = true

	# Register the already-selected deck now that we know we're the host
	if not deck_select.current_selection.is_empty():
		_host_deck_ready = DecklistManager.select_deck_for_player(0, deck_select.current_selection)

	status_label.text = tr("STR_ONLINE_SHARE_CODE")


func _on_join_pressed() -> void:
	SfxManager.play("ui_click")
	var code := code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = tr("STR_ONLINE_ENTER_CODE")
		return

	if NetworkManager.USE_DEDICATED_SERVER:
		if not await _ensure_connected():
			return
		NetworkManager.join_room(code)
		return

	_set_buttons_locked(true)
	status_label.text = tr("STR_ONLINE_CONNECTING_RELAY")

	var err := await NetworkManager.join_online(code)
	if err != OK:
		status_label.text = tr("STR_ONLINE_CONNECT_FAILED_FMT") % err
		_set_buttons_locked(false)
		return

	status_label.text = tr("STR_ONLINE_CONNECTING_HOST")


func _on_deck_selected(deck_name: String) -> void:
	if deck_name.is_empty():
		return

	if NetworkManager.USE_DEDICATED_SERVER:
		if _seated:
			_send_deck(deck_name)
		return

	if NetworkManager.is_host():
		_host_deck_ready = DecklistManager.select_deck_for_player(0, deck_name)
		_update_start_button()
	elif NetworkManager.is_multiplayer():
		var data := DecklistManager.load_decklist(deck_name)
		if data.is_empty():
			return
		var payload := JSON.stringify({
			"deck_name": deck_name,
			"monster": data["monster"],
			"main": data["main"],
		})
		_rpc_send_deck_data.rpc_id(NetworkManager.host_peer_id, payload)
		status_label.text = tr("STR_LAN_DECK_SENT_FMT") % deck_name


# --- Relay flow (host-client) ---

func _on_player_connected(_peer_id: int) -> void:
	if NetworkManager.is_host():
		status_label.text = tr("STR_LAN_OPPONENT_CONNECTED_HOST")
		_update_start_button()
	else:
		deck_select.set_header(tr("STR_DS_SELECT_YOUR_DECK"))
		if not deck_select.current_selection.is_empty():
			_on_deck_selected(deck_select.current_selection)
		else:
			status_label.text = tr("STR_LAN_CONNECTED_SELECT_DECK")


func _on_player_disconnected(_peer_id: int) -> void:
	if _version_mismatch_shown:
		return
	if not NetworkManager.version_verified:
		status_label.text = tr("STR_LAN_OPPONENT_DIFFERENT_VERSION_FMT") % NetworkManager.GAME_VERSION
	else:
		status_label.text = tr("STR_LAN_OPPONENT_DISCONNECTED")
	_set_buttons_locked(false)
	start_button.visible = false
	_client_deck_received = false
	_client_deck_name = ""


func _on_start_pressed() -> void:
	SfxManager.play("ui_click")
	if not NetworkManager.is_host():
		return
	NetworkManager.start_lan_game()


func _update_start_button() -> void:
	if not NetworkManager.is_host():
		start_button.visible = false
		return
	var can_start: bool = NetworkManager.opponent_connected and NetworkManager.version_verified and _host_deck_ready and _client_deck_received
	start_button.visible = can_start
	start_button.disabled = not can_start
	if can_start:
		status_label.text = tr("STR_LAN_OPPONENT_DECK_READY")


## Client sends their deck data to host (relay/LAN host-client only)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_deck_data(payload_json: String) -> void:
	if not NetworkManager.is_host():
		return
	var data: Dictionary = JSON.parse_string(payload_json)
	if data.is_empty():
		return
	_client_deck_name = data.get("deck_name", "Unknown")
	var monster_entries: Array = data.get("monster", [])
	var main_entries: Array = data.get("main", [])
	DecklistManager.set_player_deck_from_entries(1, _client_deck_name, monster_entries, main_entries)
	_client_deck_received = true
	_update_start_button()


# --- Dedicated-server flow (symmetric) ---

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


# --- Shared ---

func _on_connection_failed() -> void:
	status_label.text = tr("STR_ONLINE_CONNECTION_FAILED_RETRY")
	_set_buttons_locked(false)


func _on_version_mismatch(local_version: String, remote_version: String) -> void:
	_version_mismatch_shown = true
	status_label.text = tr("STR_LAN_VERSION_MISMATCH_FMT") % [local_version, remote_version]
	_set_buttons_locked(false)
	start_button.visible = false


func _set_buttons_locked(locked: bool) -> void:
	host_button.disabled = locked
	join_button.disabled = locked
	code_edit.editable = not locked


func _on_copy_pressed() -> void:
	SfxManager.play("ui_click")
	var code := code_label.text if NetworkManager.USE_DEDICATED_SERVER else NetworkManager.get_game_code()
	DisplayServer.clipboard_set(code)
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
