extends Control

@onready var create_button: Button = $MarginContainer/HBoxContainer/LobbyPanel/ActionRow/CreateButton
@onready var refresh_button: Button = $MarginContainer/HBoxContainer/LobbyPanel/ActionRow/RefreshButton
@onready var status_label: Label = $MarginContainer/HBoxContainer/LobbyPanel/StatusLabel
@onready var room_list: VBoxContainer = $MarginContainer/HBoxContainer/LobbyPanel/RoomScroll/RoomList
@onready var deck_select: PanelContainer = $MarginContainer/HBoxContainer/DeckSelect
@onready var back_button: Button = $MarginContainer/HBoxContainer/LobbyPanel/BackButton

var _host_deck_ready: bool = false
var _client_deck_received: bool = false
var _client_deck_name: String = ""
var _version_mismatch_shown: bool = false
var _is_hosting: bool = false
var _is_joining: bool = false
var _deck_selected: bool = false


func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	back_button.pressed.connect(_on_back_pressed)
	deck_select.deck_selected.connect(_on_deck_selected)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.version_mismatch.connect(_on_version_mismatch)
	NetworkManager.version_verified_ok.connect(_try_auto_start)

	DecklistManager.clear_selections()

	# Require deck selection before Create/Join
	create_button.disabled = true
	status_label.text = "Select a deck, then create or join a lobby."

	# Check if a deck is already selected
	if not deck_select.current_selection.is_empty():
		_on_deck_selected(deck_select.current_selection)

	_fetch_rooms()


func _fetch_rooms() -> void:
	refresh_button.disabled = true

	var rooms: Array = await NetworkManager.fetch_public_rooms()

	refresh_button.disabled = false

	# Clear existing room entries
	for child in room_list.get_children():
		child.queue_free()

	if rooms.is_empty():
		if _deck_selected and not _is_hosting and not _is_joining:
			status_label.text = "No public lobbies available. Create one!"
		return

	if not _is_hosting and not _is_joining:
		status_label.text = "%d lobby(s) found:" % rooms.size()

	for room in rooms:
		var code: String = room.get("code", "")
		var host_name: String = room.get("name", code)
		if code.is_empty():
			continue

		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 15)

		var label := Label.new()
		label.text = "Room %s" % ChatFilter.filter(host_name)
		label.add_theme_font_size_override("font_size", 18)
		row.add_child(label)

		var join_btn := Button.new()
		join_btn.text = "Join"
		join_btn.custom_minimum_size = Vector2(80, 36)
		join_btn.add_theme_font_size_override("font_size", 16)
		join_btn.disabled = not _deck_selected or _is_hosting or _is_joining
		join_btn.pressed.connect(_on_join_room.bind(code))
		row.add_child(join_btn)

		room_list.add_child(row)


func _on_refresh_pressed() -> void:
	if _is_hosting or _is_joining:
		return
	_fetch_rooms()


func _on_create_pressed() -> void:
	create_button.disabled = true
	refresh_button.disabled = true
	_is_hosting = true
	_set_join_buttons_disabled(true)
	status_label.text = "Creating public lobby..."

	var err := await NetworkManager.host_public()
	if err != OK:
		status_label.text = "Failed to create lobby (error %d)" % err
		create_button.disabled = not _deck_selected
		refresh_button.disabled = false
		_is_hosting = false
		_set_join_buttons_disabled(not _deck_selected)
		return

	_host_deck_ready = DecklistManager.select_deck_for_player(0, deck_select.current_selection)
	status_label.text = "Lobby created! Waiting for opponent..."


func _on_join_room(code: String) -> void:
	if not _deck_selected:
		status_label.text = "Select a deck first."
		return
	create_button.disabled = true
	refresh_button.disabled = true
	_is_joining = true
	_set_join_buttons_disabled(true)
	status_label.text = "Joining room %s..." % code

	var err := await NetworkManager.join_online(code)
	if err != OK:
		status_label.text = "Failed to join room (error %d)" % err
		create_button.disabled = not _deck_selected
		refresh_button.disabled = false
		_is_joining = false
		_set_join_buttons_disabled(not _deck_selected)
		return

	status_label.text = "Connecting to host..."


func _on_player_connected(_peer_id: int) -> void:
	if NetworkManager.is_host():
		status_label.text = "Opponent connected! Starting game..."
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
		status_label.text = "Connected! Waiting for game to start..."


func _on_player_disconnected(_peer_id: int) -> void:
	if _version_mismatch_shown:
		return
	if not NetworkManager.version_verified:
		status_label.text = "Opponent has a different version (you: v%s)." % NetworkManager.GAME_VERSION
	else:
		status_label.text = "Opponent disconnected."
	create_button.disabled = not _deck_selected
	refresh_button.disabled = false
	_client_deck_received = false
	_client_deck_name = ""
	_is_hosting = false
	_is_joining = false
	_set_join_buttons_disabled(not _deck_selected)


func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
	create_button.disabled = not _deck_selected
	refresh_button.disabled = false
	_is_hosting = false
	_is_joining = false
	_set_join_buttons_disabled(not _deck_selected)


func _on_version_mismatch(local_version: String, remote_version: String) -> void:
	_version_mismatch_shown = true
	status_label.text = "Version mismatch! You: v%s, Opponent: v%s" % [local_version, remote_version]
	create_button.disabled = not _deck_selected
	refresh_button.disabled = false
	_is_hosting = false
	_is_joining = false
	_set_join_buttons_disabled(not _deck_selected)


func _on_deck_selected(deck_name: String) -> void:
	_deck_selected = not deck_name.is_empty()
	if not _is_hosting and not _is_joining:
		create_button.disabled = not _deck_selected
		_set_join_buttons_disabled(not _deck_selected)
		if _deck_selected:
			status_label.text = "Deck selected. Create or join a lobby!"


func _on_back_pressed() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/ui/OnlinePlay.tscn")


func _try_auto_start() -> void:
	if not NetworkManager.is_host():
		return
	if NetworkManager.opponent_connected and NetworkManager.version_verified and _host_deck_ready and _client_deck_received:
		status_label.text = "Starting game..."
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
