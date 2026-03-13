extends Control

@onready var host_button: Button = $CenterContainer/VBoxContainer/HostPanel/HostButton
@onready var port_edit: LineEdit = $CenterContainer/VBoxContainer/HostPanel/PortEdit
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinPanel/JoinButton
@onready var ip_edit: LineEdit = $CenterContainer/VBoxContainer/JoinPanel/IpEdit
@onready var join_port_edit: LineEdit = $CenterContainer/VBoxContainer/JoinPanel/JoinPortEdit
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var deck_select: VBoxContainer = $CenterContainer/VBoxContainer/DeckSelect
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

var _host_deck_ready: bool = false
var _client_deck_received: bool = false
var _client_deck_name: String = ""
var _version_mismatch_shown: bool = false


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	deck_select.deck_selected.connect(_on_deck_selected)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.version_mismatch.connect(_on_version_mismatch)
	NetworkManager.version_verified_ok.connect(_update_start_button)

	DecklistManager.clear_selections()

	start_button.visible = false
	status_label.text = ""

	# If a deck is already selected, keep it
	if not deck_select.current_selection.is_empty():
		_on_deck_selected(deck_select.current_selection)


func _on_host_pressed() -> void:
	var port := int(port_edit.text) if port_edit.text.is_valid_int() else NetworkManager.DEFAULT_PORT
	var err := NetworkManager.host_game(port)
	if err != OK:
		status_label.text = "Failed to host (port %d may be in use)" % port
		return

	host_button.disabled = true
	join_button.disabled = true
	ip_edit.editable = false
	join_port_edit.editable = false
	port_edit.editable = false

	# Register the already-selected deck now that we know we're the host
	if not deck_select.current_selection.is_empty():
		_host_deck_ready = DecklistManager.select_deck_for_player(0, deck_select.current_selection)

	var local_ip := _get_local_ip()
	status_label.text = "Hosting on %s:%d\nWaiting for opponent..." % [local_ip, port]


func _on_join_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Enter the host's IP address"
		return

	var port := int(join_port_edit.text) if join_port_edit.text.is_valid_int() else NetworkManager.DEFAULT_PORT
	var err := NetworkManager.join_game(ip, port)
	if err != OK:
		status_label.text = "Failed to connect"
		return

	host_button.disabled = true
	join_button.disabled = true
	ip_edit.editable = false
	join_port_edit.editable = false
	port_edit.editable = false
	status_label.text = "Connecting to %s:%d..." % [ip, port]


func _on_player_connected(_peer_id: int) -> void:
	if NetworkManager.is_host():
		status_label.text = "Opponent connected! Select a deck and press Start."
		_update_start_button()
	else:
		deck_select.set_header("SELECT YOUR DECK")
		# If the client already has a deck selected, send it now
		if not deck_select.current_selection.is_empty():
			_on_deck_selected(deck_select.current_selection)
		else:
			status_label.text = "Connected! Select a deck."


func _on_player_disconnected(_peer_id: int) -> void:
	if _version_mismatch_shown:
		return
	if not NetworkManager.version_verified:
		status_label.text = "Opponent has a different version (you: v%s)." % NetworkManager.GAME_VERSION
	else:
		status_label.text = "Opponent disconnected."
	host_button.disabled = false
	join_button.disabled = false
	ip_edit.editable = true
	join_port_edit.editable = true
	port_edit.editable = true
	start_button.visible = false
	_client_deck_received = false
	_client_deck_name = ""


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the IP and try again."
	host_button.disabled = false
	join_button.disabled = false
	ip_edit.editable = true
	join_port_edit.editable = true
	port_edit.editable = true


func _on_version_mismatch(local_version: String, remote_version: String) -> void:
	_version_mismatch_shown = true
	status_label.text = "Version mismatch! You: v%s, Opponent: v%s" % [local_version, remote_version]
	host_button.disabled = false
	join_button.disabled = false
	ip_edit.editable = true
	join_port_edit.editable = true
	port_edit.editable = true
	start_button.visible = false


func _on_deck_selected(deck_name: String) -> void:
	if deck_name.is_empty():
		return

	if NetworkManager.is_host():
		# Host selects as player 0
		_host_deck_ready = DecklistManager.select_deck_for_player(0, deck_name)
		_update_start_button()
	elif NetworkManager.is_multiplayer():
		# Client selects and sends deck data to host
		var data := DecklistManager.load_decklist(deck_name)
		if data.is_empty():
			return
		var payload := JSON.stringify({
			"deck_name": deck_name,
			"monster": data["monster"],
			"main": data["main"],
		})
		_rpc_send_deck_data.rpc_id(NetworkManager.host_peer_id, payload)
		status_label.text = "Deck \"%s\" sent to host. Waiting for host to start..." % deck_name


func _on_start_pressed() -> void:
	if not NetworkManager.is_host():
		return
	NetworkManager.start_lan_game()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_back_pressed() -> void:
	NetworkManager.disconnect_game()
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")


func _update_start_button() -> void:
	if not NetworkManager.is_host():
		start_button.visible = false
		return
	var can_start: bool = NetworkManager.opponent_connected and NetworkManager.version_verified and _host_deck_ready and _client_deck_received
	start_button.visible = can_start
	start_button.disabled = not can_start
	if can_start:
		status_label.text = "Opponent deck received. Ready to start!"


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


func _get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		# Prefer 192.168.x.x or 10.x.x.x LAN addresses
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
	return "127.0.0.1"
