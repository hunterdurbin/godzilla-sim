extends Control

@onready var create_button: Button = $CenterContainer/VBoxContainer/ActionRow/CreateButton
@onready var refresh_button: Button = $CenterContainer/VBoxContainer/ActionRow/RefreshButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var room_list: VBoxContainer = $CenterContainer/VBoxContainer/RoomScroll/RoomList
@onready var deck_select: VBoxContainer = $CenterContainer/VBoxContainer/SettingsRow/DeckSelect
@onready var mode_dropdown: OptionButton = $CenterContainer/VBoxContainer/SettingsRow/ModeSelect/ModeDropdown
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

var _host_deck_ready: bool = false
var _client_deck_received: bool = false
var _client_deck_name: String = ""
var _version_mismatch_shown: bool = false
var _is_hosting: bool = false
var _is_joining: bool = false
var _deck_valid: bool = false
var _validation_errors: Array[String] = []


func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	back_button.pressed.connect(_on_back_pressed)
	deck_select.deck_selected.connect(_on_deck_selected)

	# Populate game mode dropdown from centralized list
	for gm in GameModeValidator.MODES:
		mode_dropdown.add_item(tr(gm.label))
	mode_dropdown.select(0)
	mode_dropdown.item_selected.connect(_on_mode_selected)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.version_mismatch.connect(_on_version_mismatch)
	NetworkManager.version_verified_ok.connect(_try_auto_start)

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


func _on_create_pressed() -> void:
	SfxManager.play("ui_click")
	create_button.disabled = true
	refresh_button.disabled = true
	_is_hosting = true
	_set_join_buttons_disabled(true)
	deck_select.deck_dropdown.disabled = true
	mode_dropdown.disabled = true
	status_label.text = tr("STR_PUBLIC_CREATING")

	var err := await NetworkManager.host_public(_get_selected_mode())
	if err != OK:
		status_label.text = tr("STR_PUBLIC_CREATE_FAILED_FMT") % err
		create_button.disabled = not _deck_valid
		refresh_button.disabled = false
		_is_hosting = false
		_set_join_buttons_disabled(not _deck_valid)
		deck_select.deck_dropdown.disabled = false
		mode_dropdown.disabled = false
		return

	_host_deck_ready = DecklistManager.select_deck_for_player(0, deck_select.current_selection)
	status_label.text = tr("STR_PUBLIC_LOBBY_CREATED")


func _on_join_room(code: String) -> void:
	SfxManager.play("ui_click")
	if not _deck_valid:
		status_label.text = tr("STR_PUBLIC_DECK_INVALID_MODE")
		return
	create_button.disabled = true
	refresh_button.disabled = true
	_is_joining = true
	_set_join_buttons_disabled(true)
	deck_select.deck_dropdown.disabled = true
	mode_dropdown.disabled = true
	status_label.text = tr("STR_PUBLIC_JOINING_FMT") % code

	var err := await NetworkManager.join_online(code)
	if err != OK:
		status_label.text = tr("STR_PUBLIC_JOIN_FAILED_FMT") % err
		create_button.disabled = not _deck_valid
		refresh_button.disabled = false
		_is_joining = false
		_set_join_buttons_disabled(not _deck_valid)
		deck_select.deck_dropdown.disabled = false
		mode_dropdown.disabled = false
		_fetch_rooms()
		return

	status_label.text = tr("STR_ONLINE_CONNECTING_HOST")


func _on_player_connected(_peer_id: int) -> void:
	if NetworkManager.is_host():
		status_label.text = tr("STR_PUBLIC_OPPONENT_CONNECTED_STARTING")
		_try_auto_start()
	else:
		# Client: send deck immediately
		var data := DecklistManager.load_decklist(deck_select.current_selection)
		if data.is_empty():
			return
		var payload := JSON.stringify({
			"deck_name": deck_select.current_selection,
			"monster": data["monster"],
			"main": data["main"],
		})
		_rpc_send_deck_data.rpc_id(NetworkManager.host_peer_id, payload)
		status_label.text = tr("STR_PUBLIC_CONNECTED_WAITING")


func _on_player_disconnected(_peer_id: int) -> void:
	if _version_mismatch_shown:
		return
	if not NetworkManager.version_verified:
		status_label.text = tr("STR_LAN_OPPONENT_DIFFERENT_VERSION_FMT") % NetworkManager.GAME_VERSION
	else:
		status_label.text = tr("STR_LAN_OPPONENT_DISCONNECTED")
	create_button.disabled = not _deck_valid
	refresh_button.disabled = false
	_client_deck_received = false
	_client_deck_name = ""
	_is_hosting = false
	_is_joining = false
	_set_join_buttons_disabled(not _deck_valid)
	deck_select.deck_dropdown.disabled = false
	mode_dropdown.disabled = false


func _on_connection_failed() -> void:
	status_label.text = tr("STR_PUBLIC_CONNECTION_FAILED")
	create_button.disabled = not _deck_valid
	refresh_button.disabled = false
	_is_hosting = false
	_is_joining = false
	_set_join_buttons_disabled(not _deck_valid)
	deck_select.deck_dropdown.disabled = false
	mode_dropdown.disabled = false


func _on_version_mismatch(local_version: String, remote_version: String) -> void:
	_version_mismatch_shown = true
	status_label.text = tr("STR_LAN_VERSION_MISMATCH_FMT") % [local_version, remote_version]
	create_button.disabled = not _deck_valid
	refresh_button.disabled = false
	_is_hosting = false
	_is_joining = false
	_set_join_buttons_disabled(not _deck_valid)
	deck_select.deck_dropdown.disabled = false
	mode_dropdown.disabled = false


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


func _try_auto_start() -> void:
	if not NetworkManager.is_host():
		return
	if NetworkManager.opponent_connected and NetworkManager.version_verified and _host_deck_ready and _client_deck_received:
		status_label.text = tr("STR_PUBLIC_STARTING_GAME")
		NetworkManager.start_lan_game()


func _set_join_buttons_disabled(disabled: bool) -> void:
	for child in room_list.get_children():
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is Button:
					sub.disabled = disabled


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
	_try_auto_start()
