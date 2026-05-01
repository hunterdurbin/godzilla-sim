class_name FirstPlayerOverlay
extends Control

## Drop-in coin-flip / first-player choice modal.
##
## API:
##   show_choice(chooser_id: int)  → present "Go First / Go Second" buttons
##   show_waiting(prompt_key := "STR_GB_COIN_FLIP_WAITING") → spinner-style
##                                  message while the other player chooses
##   hide_choice()                 → dismiss
##
## Emits `choice_made(chosen_player_id)` when the local player presses
## one of the buttons. Caller (template controller) routes this to
## `session.start_game(chosen_player_id)` plus any RPC traffic for
## multiplayer.

signal choice_made(chosen_player_id: int)

@onready var _bg: ColorRect = $Bg
@onready var _panel: PanelContainer = $Panel
@onready var _prompt: Label = $Panel/VBox/Prompt
@onready var _row: HBoxContainer = $Panel/VBox/Row
@onready var _btn_first: Button = $Panel/VBox/Row/GoFirst
@onready var _btn_second: Button = $Panel/VBox/Row/GoSecond

var _chooser_id: int = 0


func _ready() -> void:
	visible = false
	_btn_first.pressed.connect(_on_go_first)
	_btn_second.pressed.connect(_on_go_second)


## Show the two-button choice. `chooser_id` is the player_id who gets
## to decide — the resulting `choice_made` emits the chosen player's id
## (i.e. who goes first), which may be `chooser_id` or `1 - chooser_id`
## depending on the button pressed.
func show_choice(chooser_id: int) -> void:
	_chooser_id = chooser_id
	_prompt.text = tr("STR_GB_COIN_FLIP_WON")
	_row.visible = true
	visible = true


## Show the waiting-for-other-player message. No buttons.
func show_waiting() -> void:
	_prompt.text = tr("STR_GB_COIN_FLIP_WAITING")
	_row.visible = false
	visible = true


func hide_choice() -> void:
	visible = false


func _on_go_first() -> void:
	choice_made.emit(_chooser_id)
	hide_choice()


func _on_go_second() -> void:
	choice_made.emit(1 - _chooser_id)
	hide_choice()
