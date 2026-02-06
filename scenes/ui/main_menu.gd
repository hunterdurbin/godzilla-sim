extends Control

@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var lan_button: Button = $CenterContainer/VBoxContainer/LanButton
@onready var deck_select: PanelContainer = $CenterContainer/VBoxContainer/DeckSelect


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	start_button.disabled = true
	lan_button.pressed.connect(_on_lan_pressed)
	deck_select.deck_selected.connect(_on_deck_selected)
	# DeckSelect's _ready fires before ours, so it may have already selected a deck
	if not deck_select.current_selection.is_empty():
		_on_deck_selected(deck_select.current_selection)


func _on_deck_selected(deck_name: String) -> void:
	DecklistManager.select_deck(deck_name)
	start_button.disabled = false
	start_button.grab_focus()


func _on_start_pressed() -> void:
	NetworkManager.mode = NetworkManager.Mode.SOLO
	get_tree().change_scene_to_file("res://scenes/board/GameBoard.tscn")


func _on_lan_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/LanLobby.tscn")
