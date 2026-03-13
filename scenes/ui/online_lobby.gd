extends Control

@onready var host_button: Button = $CenterContainer/VBoxContainer/HostPanel/HostButton
@onready var code_label: Label = $CenterContainer/VBoxContainer/HostPanel/CodeLabel
@onready var copy_button: Button = $CenterContainer/VBoxContainer/HostPanel/CopyButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinPanel/JoinButton
@onready var code_edit: LineEdit = $CenterContainer/VBoxContainer/JoinPanel/CodeEdit
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
	copy_button.pressed.connect(_on_copy_pressed)
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

	code_label.text = NetworkManager.get_game_code()
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
	DisplayServer.clipboard_set(NetworkManager.get_game_code())
	copy_button.text = "Copied!"
	await get_tree().create_timer(1.5).timeout
	copy_button.text = "Copy"


func _on_player_connected(_peer_id: int) -> void:
	print("[Lobby] _on_player_connected peer=%d is_host=%s" % [_peer_id, NetworkManager.is_host()])
	if NetworkManager.is_host():
		status_label.text = "Opponent connected! Select a deck and press Start."
		_update_start_button()
	else:
		deck_select.set_header("SELECT YOUR DECK")
		print("[Lobby] Client current_selection='%s'" % deck_select.current_selection)
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
	code_edit.editable = true
	start_button.visible = false
	_client_deck_received = false
	_client_deck_name = ""


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the code and try again."
	host_button.disabled = false
	join_button.disabled = false
	code_edit.editable = true


func _on_version_mismatch(local_version: String, remote_version: String) -> void:
	_version_mismatch_shown = true
	status_label.text = "Version mismatch! You: v%s, Opponent: v%s" % [local_version, remote_version]
	host_button.disabled = false
	join_button.disabled = false
	code_edit.editable = true
	start_button.visible = false


func _on_deck_selected(deck_name: String) -> void:
	print("[Lobby] _on_deck_selected deck='%s' is_host=%s is_mp=%s" % [deck_name, NetworkManager.is_host(), NetworkManager.is_multiplayer()])
	if deck_name.is_empty():
		return

	if NetworkManager.is_host():
		_host_deck_ready = DecklistManager.select_deck_for_player(0, deck_name)
		print("[Lobby] Host deck ready=%s" % _host_deck_ready)
		_update_start_button()
	elif NetworkManager.is_multiplayer():
		var data := DecklistManager.load_decklist(deck_name)
		if data.is_empty():
			print("[Lobby] Client deck data empty, skipping send")
			return
		var payload := JSON.stringify({
			"deck_name": deck_name,
			"monster": data["monster"],
			"main": data["main"],
		})
		print("[Lobby] Client sending deck RPC to host")
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
	NetworkManager.change_scene("res://scenes/ui/OnlinePlay.tscn")


func _update_start_button() -> void:
	if not NetworkManager.is_host():
		start_button.visible = false
		return
	var can_start: bool = NetworkManager.opponent_connected and NetworkManager.version_verified and _host_deck_ready and _client_deck_received
	print("[Lobby] _update_start_button: opponent=%s version=%s host_deck=%s client_deck=%s -> can_start=%s" % [NetworkManager.opponent_connected, NetworkManager.version_verified, _host_deck_ready, _client_deck_received, can_start])
	start_button.visible = can_start
	start_button.disabled = not can_start
	if can_start:
		status_label.text = "Opponent deck received. Ready to start!"


## Client sends their deck data to host
@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_deck_data(payload_json: String) -> void:
	print("[Lobby] _rpc_send_deck_data received, is_host=%s" % NetworkManager.is_host())
	if not NetworkManager.is_host():
		return
	var data: Dictionary = JSON.parse_string(payload_json)
	if data.is_empty():
		print("[Lobby] Deck payload parse failed")
		return
	_client_deck_name = data.get("deck_name", "Unknown")
	print("[Lobby] Host received client deck: '%s'" % _client_deck_name)
	var monster_entries: Array = data.get("monster", [])
	var main_entries: Array = data.get("main", [])
	DecklistManager.set_player_deck_from_entries(1, _client_deck_name, monster_entries, main_entries)
	_client_deck_received = true
	_update_start_button()
