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
@onready var end_game_panel: PanelContainer = $EndGamePanel


func _ready() -> void:
	menu_button.pressed.connect(_on_menu_pressed)
	end_game_panel.menu_pressed.connect(_on_menu_pressed)
	end_game_panel.rematch_pressed.connect(_on_rematch_pressed)
	super()


func _on_menu_pressed() -> void:
	NetworkManager.is_in_game = false
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")


func _on_rematch_pressed() -> void:
	# Minimal rematch path: reload the same scene. Full host/client
	# rematch synchronization (the legacy game_board.gd flow) is out
	# of scope for the template — designers can override this hook.
	NetworkManager.change_scene(scene_file_path)
