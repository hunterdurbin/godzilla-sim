extends "res://scenes/board/game_board_base.gd"

## Stub controller for the EnhancedGameBoard test scene. Inherits from
## game_board_base.gd, so all session bootstrap (TurnManager, RPCs,
## EffectUIRouter, overlay registration) is handled by the base.
##
## This file only wires the Return-to-Menu button. Designers can add
## visual layout to BoardLayoutSlot, drop HUD primitives into the
## LocalSeat / OpponentSeat containers, and override base hooks
## (`_on_phase_started`, `_on_turn_started`, etc.) here for visual
## updates. Everything self-binds via tree-walk lookup — no extra
## wiring code needed.

@onready var menu_button: Button = $TopBar/MenuButton


func _on_host_ready() -> void:
	menu_button.pressed.connect(_on_menu_pressed)


func _on_client_ready() -> void:
	menu_button.pressed.connect(_on_menu_pressed)


func _on_menu_pressed() -> void:
	NetworkManager.is_in_game = false
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")
