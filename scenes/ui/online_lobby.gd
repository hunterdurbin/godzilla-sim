extends Control

@onready var host_button: Button = $CenterContainer/VBoxContainer/HostPanel/HostButton
@onready var code_label: Label = $CenterContainer/VBoxContainer/HostPanel/CodeLabel
@onready var copy_button: Button = $CenterContainer/VBoxContainer/HostPanel/CopyButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinPanel/JoinButton
@onready var code_edit: LineEdit = $CenterContainer/VBoxContainer/JoinPanel/CodeEdit
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var deck_select: PanelContainer = $CenterContainer/VBoxContainer/DeckSelect
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

var _host_deck_ready: bool = false
var _client_deck_received: bool = false
var _client_deck_name: String = ""


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	deck_select.deck_selected.connect(_on_deck_selected)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	DecklistManager.clear_selections()

	start_button.visible = false
	copy_button.visible = false
	code_label.text = ""
	status_label.text = ""


func _on_host_pressed() -> void:
	host_button.disabled = true
	join_button.disabled = true
	code_edit.editable = false
	status_label.text = "Connecting to relay server..."

	var err := await NetworkManager.host_online()
	if err != OK:
		status_label.text = "Failed to connect to relay server (error %d)" % err
		host_button.disabled = false
		join_button.disabled = false
		code_edit.editable = true
		return

	code_label.text = Noray.oid
	copy_button.visible = true

	# Register the already-selected deck now that we know we're the host
	if not deck_select.current_selection.is_empty():
		_host_deck_ready = DecklistManager.select_deck_for_player(0, deck_select.current_selection)

	status_label.text = "Share this game code with your opponent:"


func _on_join_pressed() -> void:
	var code := code_edit.text.strip_edges()
	if code.is_empty():
		status_label.text = "Enter the host's game code"
		return

	host_button.disabled = true
	join_button.disabled = true
	code_edit.editable = false
	status_label.text = "Connecting to relay server..."

	var err := await NetworkManager.join_online(code)
	if err != OK:
		status_label.text = "Failed to connect (error %d)" % err
		host_button.disabled = false
		join_button.disabled = false
		code_edit.editable = true
		return

	status_label.text = "Connecting to host..."


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(Noray.oid)
	copy_button.text = "Copied!"
	await get_tree().create_timer(1.5).timeout
	copy_button.text = "Copy"


func _on_player_connected(_peer_id: int) -> void:
	if NetworkManager.is_host():
		status_label.text = "Opponent connected! Select a deck and press Start."
		_update_start_button()
	else:
		deck_select.set_header("SELECT YOUR DECK")
		if not deck_select.current_selection.is_empty():
			_on_deck_selected(deck_select.current_selection)
		else:
			status_label.text = "Connected! Select a deck."


func _on_player_disconnected(_peer_id: int) -> void:
	status_label.text = "Opponent disconnected."
	start_button.visible = false
	_client_deck_received = false
	_client_deck_name = ""


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the code and try again."
	host_button.disabled = false
	join_button.disabled = false
	code_edit.editable = true


func _on_deck_selected(deck_name: String) -> void:
	if deck_name.is_empty():
		return

	if NetworkManager.is_host():
		_host_deck_ready = DecklistManager.select_deck_for_player(0, deck_name)
		_update_start_button()
	else:
		var data := DecklistManager.load_decklist(deck_name)
		if data.is_empty():
			return
		var payload := JSON.stringify({
			"deck_name": deck_name,
			"monster": data["monster"],
			"main": data["main"],
		})
		_rpc_send_deck_data.rpc_id(1, payload)
		status_label.text = "Deck \"%s\" sent to host. Waiting for host to start..." % deck_name


func _on_start_pressed() -> void:
	if not NetworkManager.is_host():
		return
	NetworkManager.start_lan_game()


func _on_back_pressed() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


func _update_start_button() -> void:
	if not NetworkManager.is_host():
		start_button.visible = false
		return
	var can_start: bool = NetworkManager.opponent_connected and _host_deck_ready and _client_deck_received
	start_button.visible = can_start
	start_button.disabled = not can_start
	if can_start:
		status_label.text = "Opponent selected: \"%s\"\nReady to start!" % _client_deck_name


## Client sends their deck data to host
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
