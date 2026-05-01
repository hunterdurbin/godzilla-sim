extends "res://scenes/board/game_board_base.gd"

## GameBoardTemplate — pre-populated drop-in starter scene.
##
## Inherits everything from game_board_base.gd. Adds only one piece of
## scene-specific wiring: the Return-to-Menu button at the top.
##
## A designer who inherits GameBoardTemplate.tscn gets a working board
## with both seats populated, HUD, action panel, and log. They reskin
## visuals and ship — no engine wiring needed.

@onready var menu_button: Button = $TopBar/MenuButton


func _ready() -> void:
	menu_button.pressed.connect(_on_menu_pressed)
	super()


func _on_menu_pressed() -> void:
	NetworkManager.is_in_game = false
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")
