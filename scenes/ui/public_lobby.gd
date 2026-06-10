extends Control

## Public matchmaking lobby — runs against the dedicated game server.
##
## Flow is symmetric: creating a room registers it in the server's public
## list; joining takes the open seat. Each player submits their deck after
## being seated, and the SERVER starts the match once both decks are in and
## both players are present (the scene change is driven by NetworkManager on
## the START message — there is no host-side start button).
##
## "Play vs Bot While You Wait": entering a lobby-bot game sends BUSY so the
## server holds the match; returning sends READY and the match starts if an
## opponent is waiting with a deck.

@onready var create_button: Button = $CenterContainer/VBoxContainer/ActionRow/CreateButton
@onready var refresh_button: Button = $CenterContainer/VBoxContainer/ActionRow/RefreshButton
@onready var play_bot_button: Button = $CenterContainer/VBoxContainer/ActionRow/PlayBotButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var queue_timer_label: Label = $CenterContainer/VBoxContainer/QueueTimerLabel
@onready var room_list: VBoxContainer = $CenterContainer/VBoxContainer/RoomScroll/RoomList
@onready var deck_select: VBoxContainer = $CenterContainer/VBoxContainer/SettingsRow/DeckSelect
@onready var mode_dropdown: OptionButton = $CenterContainer/VBoxContainer/SettingsRow/ModeSelect/ModeDropdown
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

var _version_mismatch_shown: bool = false
var _is_hosting: bool = false
var _is_joining: bool = false
var _deck_valid: bool = false
var _validation_errors: Array[String] = []

var _queue_timer_active: bool = false
var _queue_start_msec: int = 0


func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	play_bot_button.pressed.connect(_on_play_bot_pressed)
	back_button.pressed.connect(_on_back_pressed)
	deck_select.deck_selected.connect(_on_deck_selected)

	# Populate game mode dropdown from centralized list
	for gm in GameModeValidator.MODES:
		mode_dropdown.add_item(tr(gm.label))
	var default_idx := 0
	for i in range(GameModeValidator.MODES.size()):
		if GameModeValidator.MODES[i]["id"] == GameSettings.default_game_mode:
			default_idx = i
			break
	mode_dropdown.select(default_idx)
	mode_dropdown.item_selected.connect(_on_mode_selected)

	NetworkManager.server_seated.connect(_on_seated)
	NetworkManager.server_lobby_update.connect(_on_lobby_update)
	NetworkManager.server_error.connect(_on_server_error)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.version_mismatch.connect(_on_version_mismatch)

	# Detect re-entry from an in-lobby bot match: the server bridge and room
	# seat stay alive across that scene change (exit_lobby_bot_game already
	# sent READY), so we resume waiting without clearing the selected deck.
	var resuming := NetworkManager.mode == NetworkManager.Mode.ONLINE \
		and NetworkManager.is_public_room \
		and not NetworkManager.get_game_code().is_empty()
	if resuming:
		_resume_hosting_state()
		_fetch_rooms()
		return

	DecklistManager.clear_selections()

	# Require valid deck before Create/Join
	create_button.disabled = true
	status_label.text = tr("STR_PUBLIC_SELECT_DECK")

	# Check if a deck is already selected
	if not deck_select.current_selection.is_empty():
		_on_deck_selected(deck_select.current_selection)

	_fetch_rooms()


func _get_selected_mode() -> String:
	return GameModeValidator.MODES[mode_dropdown.selected].id


func _on_mode_selected(_index: int) -> void:
	if not _is_hosting and not _is_joining:
		_validate_current_deck()
		_update_action_buttons()
		_update_deck_status()
		_fetch_rooms()


func _validate_current_deck() -> void:
	if deck_select.current_selection.is_empty():
		_deck_valid = false
		_validation_errors = []
		return

	var data := DecklistManager.load_decklist(deck_select.current_selection)
	if data.is_empty():
		_deck_valid = false
		_validation_errors = [tr("STR_PUBLIC_DECK_LOAD_FAILED")]
		return

	_validation_errors = GameModeValidator.validate(
		_get_selected_mode(), data["monster"], data["main"])
	_deck_valid = _validation_errors.is_empty()


func _update_action_buttons() -> void:
	if _is_hosting or _is_joining:
		return
	create_button.disabled = not _deck_valid
	_set_join_buttons_disabled(not _deck_valid)


func _fetch_rooms() -> void:
	refresh_button.disabled = true

	var rooms: Array = await NetworkManager.fetch_public_rooms(_get_selected_mode())

	refresh_button.disabled = false

	# Clear existing room entries
	for child in room_list.get_children():
		child.queue_free()

	if rooms.is_empty():
		if _deck_valid and not _is_hosting and not _is_joining:
			status_label.text = tr("STR_PUBLIC_NO_LOBBIES")
		return

	if not _is_hosting and not _is_joining:
		status_label.text = tr("STR_PUBLIC_LOBBIES_FOUND_FMT") % rooms.size()

	for room in rooms:
		var code: String = room.get("code", "")
		var host_name: String = room.get("name", code)
		var room_mode: String = GameModeValidator.normalize_mode_id(room.get("mode", "rumble_west"))
		if code.is_empty():
			continue

		var mode_label: String = GameModeValidator.get_mode_label(room_mode)

		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 15)

		var label := Label.new()
		label.text = "%s  [%s]" % [ChatFilter.filter(host_name), mode_label]
		label.add_theme_font_size_override("font_size", 18)
		row.add_child(label)

		var join_btn := Button.new()
		join_btn.text = tr("STR_PUBLIC_JOIN")
		join_btn.custom_minimum_size = Vector2(80, 36)
		join_btn.add_theme_font_size_override("font_size", 16)
		join_btn.disabled = not _deck_valid or _is_hosting or _is_joining
		join_btn.pressed.connect(_on_join_room.bind(code))
		row.add_child(join_btn)

		room_list.add_child(row)


func _on_refresh_pressed() -> void:
	SfxManager.play("ui_click")
	if _is_hosting or _is_joining:
		return
	_fetch_rooms()


## Connect the control-plane bridge (idempotent). Returns false on failure.
func _ensure_connected() -> bool:
	if NetworkManager.mode == NetworkManager.Mode.ONLINE and NetworkManager.server_peer != null:
		return true
	status_label.text = tr("STR_ONLINE_CONNECTING_RELAY")
	var err := await NetworkManager.connect_to_server()
	if err != OK:
		if not _version_mismatch_shown:
			status_label.text = tr("STR_PUBLIC_CONNECTION_FAILED")
		return false
	return true


func _on_create_pressed() -> void:
	SfxManager.play("ui_click")
	_lock_lobby_controls(true)
	_is_hosting = true
	status_label.text = tr("STR_PUBLIC_CREATING")

	if not await _ensure_connected():
		_is_hosting = false
		_lock_lobby_controls(false)
		return

	NetworkManager.create_room(true, _get_selected_mode())


func _on_join_room(code: String) -> void:
	SfxManager.play("ui_click")
	if not _deck_valid:
		status_label.text = tr("STR_PUBLIC_DECK_INVALID_MODE")
		return
	_lock_lobby_controls(true)
	_is_joining = true
	status_label.text = tr("STR_PUBLIC_JOINING_FMT") % code

	if not await _ensure_connected():
		_is_joining = false
		_lock_lobby_controls(false)
		_fetch_rooms()
		return

	NetworkManager.join_room(code)


func _on_seated(_room: String, _player_id: int) -> void:
	# Mirror our deck into DecklistManager so client-side lookups
	# (e.g. _show_local_starter_monster on GameBoard) work without a state RPC.
	if NetworkManager.local_player_id >= 0 and not deck_select.current_selection.is_empty():
		DecklistManager.select_deck_for_player(NetworkManager.local_player_id, deck_select.current_selection)
	NetworkManager.send_deck_to_server(deck_select.current_selection)
	if _is_hosting:
		status_label.text = tr("STR_PUBLIC_LOBBY_CREATED")
		play_bot_button.visible = true
	else:
		status_label.text = tr("STR_PUBLIC_CONNECTED_WAITING")
	_start_queue_timer()


func _on_lobby_update(info: Dictionary) -> void:
	if bool(info.get("opponent_connected", false)):
		if bool(info.get("opponent_deck_ready", false)):
			status_label.text = tr("STR_PUBLIC_OPPONENT_CONNECTED_STARTING")
		else:
			status_label.text = tr("STR_ONLINE_WAITING_OPPONENT_DECK")
	elif _is_hosting:
		status_label.text = tr("STR_PUBLIC_LOBBY_CREATED")


func _on_server_error(code: String) -> void:
	match code:
		"not_found":
			status_label.text = tr("STR_ONLINE_ROOM_NOT_FOUND")
		"full":
			status_label.text = tr("STR_ONLINE_ROOM_FULL")
		"version":
			return # version_mismatch handler shows the message
		_:
			status_label.text = tr("STR_PUBLIC_CONNECTION_FAILED")
	_stop_queue_timer()
	_is_hosting = false
	_is_joining = false
	play_bot_button.visible = false
	_lock_lobby_controls(false)
	_fetch_rooms()


func _on_connection_failed() -> void:
	status_label.text = tr("STR_PUBLIC_CONNECTION_FAILED")
	_stop_queue_timer()
	_is_hosting = false
	_is_joining = false
	play_bot_button.visible = false
	_lock_lobby_controls(false)


func _on_version_mismatch(local_version: String, remote_version: String) -> void:
	_version_mismatch_shown = true
	_stop_queue_timer()
	status_label.text = tr("STR_LAN_VERSION_MISMATCH_FMT") % [local_version, remote_version]
	_is_hosting = false
	_is_joining = false
	play_bot_button.visible = false
	_lock_lobby_controls(false)


func _on_deck_selected(_deck_name: String) -> void:
	if _is_hosting or _is_joining:
		return
	_validate_current_deck()
	_update_action_buttons()
	_update_deck_status()


func _update_deck_status() -> void:
	if deck_select.current_selection.is_empty():
		status_label.text = tr("STR_PUBLIC_SELECT_DECK")
	elif _deck_valid:
		status_label.text = tr("STR_PUBLIC_DECK_OK")
	else:
		status_label.text = tr("STR_PUBLIC_DECK_INVALID_FMT") % [
			GameModeValidator.get_mode_label(_get_selected_mode()),
			_validation_errors[0]]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_back_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.disconnect_game()
	NetworkManager.change_scene("res://scenes/ui/OnlinePlay.tscn")


func _lock_lobby_controls(locked: bool) -> void:
	create_button.disabled = locked or not _deck_valid
	refresh_button.disabled = locked
	_set_join_buttons_disabled(locked or not _deck_valid)
	deck_select.set_disabled(locked)
	mode_dropdown.disabled = locked


func _set_join_buttons_disabled(disabled: bool) -> void:
	for child in room_list.get_children():
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is Button:
					sub.disabled = disabled


# --- Play vs Bot While Waiting ---

func _on_play_bot_pressed() -> void:
	SfxManager.play("ui_click")
	if not _is_hosting:
		return
	NetworkManager.enter_lobby_bot_game(GameSettings.bot_difficulty)
	NetworkManager.change_scene("res://scenes/board/GameBoard.tscn")


func _resume_hosting_state() -> void:
	_is_hosting = true
	_deck_valid = true
	_lock_lobby_controls(true)
	play_bot_button.visible = true
	status_label.text = tr("STR_PUBLIC_LOBBY_CREATED")
	_start_queue_timer()


# --- Queue timer ---

func _start_queue_timer() -> void:
	if _queue_timer_active:
		return
	_queue_timer_active = true
	_queue_start_msec = Time.get_ticks_msec()
	queue_timer_label.visible = true
	_update_queue_timer_label()
	set_process(true)


func _stop_queue_timer() -> void:
	_queue_timer_active = false
	queue_timer_label.visible = false
	set_process(false)


func _process(_delta: float) -> void:
	if _queue_timer_active:
		_update_queue_timer_label()


func _update_queue_timer_label() -> void:
	var elapsed: int = int((Time.get_ticks_msec() - _queue_start_msec) / 1000.0)
	queue_timer_label.text = tr("STR_PUBLIC_QUEUE_TIMER_FMT") % [int(elapsed / 60.0), elapsed % 60]
