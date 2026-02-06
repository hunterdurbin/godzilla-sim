extends Control

@onready var host_button: Button = $CenterContainer/VBoxContainer/HostPanel/HostButton
@onready var port_edit: LineEdit = $CenterContainer/VBoxContainer/HostPanel/PortEdit
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinPanel/JoinButton
@onready var ip_edit: LineEdit = $CenterContainer/VBoxContainer/JoinPanel/IpEdit
@onready var join_port_edit: LineEdit = $CenterContainer/VBoxContainer/JoinPanel/JoinPortEdit
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var deck_select: PanelContainer = $CenterContainer/VBoxContainer/DeckSelect
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	deck_select.deck_selected.connect(_on_deck_selected)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)

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
		status_label.text = "Connected! Waiting for host to start..."


func _on_player_disconnected(_peer_id: int) -> void:
	status_label.text = "Opponent disconnected."
	start_button.visible = false


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the IP and try again."
	host_button.disabled = false
	join_button.disabled = false
	ip_edit.editable = true
	join_port_edit.editable = true
	port_edit.editable = true


func _on_deck_selected(deck_name: String) -> void:
	if not deck_name.is_empty():
		DecklistManager.select_deck(deck_name)
	_update_start_button()


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
	var has_deck: bool = not deck_select.current_selection.is_empty()
	var can_start: bool = NetworkManager.opponent_connected and has_deck
	start_button.visible = can_start
	start_button.disabled = not can_start


func _get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		# Prefer 192.168.x.x or 10.x.x.x LAN addresses
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
	return "127.0.0.1"
