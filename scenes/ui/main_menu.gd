extends Control

const CardScript := preload("res://scenes/cards/card.gd")

@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var lan_button: Button = $CenterContainer/VBoxContainer/LanButton
@onready var online_button: Button = $CenterContainer/VBoxContainer/OnlineButton
@onready var deck_builder_button: Button = $CenterContainer/VBoxContainer/DeckBuilderButton
@onready var options_button: Button = $OptionsButton
@onready var deck_select_p1: PanelContainer = $CenterContainer/VBoxContainer/DeckRow/DeckSelectP1
@onready var deck_select_p2: PanelContainer = $CenterContainer/VBoxContainer/DeckRow/DeckSelectP2

var _p1_ready: bool = false
var _p2_ready: bool = false


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	start_button.disabled = true
	lan_button.pressed.connect(_on_lan_pressed)
	online_button.pressed.connect(_on_online_pressed)
	deck_builder_button.pressed.connect(_on_deck_builder_pressed)
	options_button.pressed.connect(_on_options_pressed)

	DecklistManager.clear_selections()
	CardScript.clear_texture_cache()

	deck_select_p1.set_header("PLAYER 1 DECK")
	deck_select_p2.set_header("PLAYER 2 DECK")

	deck_select_p1.deck_selected.connect(_on_p1_deck_selected)
	deck_select_p2.deck_selected.connect(_on_p2_deck_selected)

	# DeckSelect's _ready fires before ours, so it may have already selected a deck
	if not deck_select_p1.current_selection.is_empty():
		_on_p1_deck_selected(deck_select_p1.current_selection)
	if not deck_select_p2.current_selection.is_empty():
		_on_p2_deck_selected(deck_select_p2.current_selection)


func _on_p1_deck_selected(deck_name: String) -> void:
	_p1_ready = not deck_name.is_empty() and DecklistManager.select_deck_for_player(0, deck_name)
	_update_start_button()


func _on_p2_deck_selected(deck_name: String) -> void:
	_p2_ready = not deck_name.is_empty() and DecklistManager.select_deck_for_player(1, deck_name)
	_update_start_button()


func _update_start_button() -> void:
	start_button.disabled = not (_p1_ready and _p2_ready)
	if not start_button.disabled:
		start_button.grab_focus()


func _on_start_pressed() -> void:
	NetworkManager.mode = NetworkManager.Mode.SOLO
	get_tree().change_scene_to_file("res://scenes/board/GameBoard.tscn")


func _on_lan_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/LanLobby.tscn")


func _on_online_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/OnlineLobby.tscn")


func _on_deck_builder_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/DeckBuilder.tscn")


func _on_options_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/Options.tscn")
