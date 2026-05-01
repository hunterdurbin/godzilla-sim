extends Control

## Drop-in action panel. The 6 main TCG actions plus Cancel/Confirm.
## Emits high-level signals; SelectionModeController owns the actual
## game-flow logic.
##
## Designer drops this scene into a GameBoard scene tree (typically
## inside the LocalSeat or alongside it) and the rest auto-wires.
##
## Contract (other panels can fulfill it without using this scene):
##   signal action_pressed(action: CardEnums.ActionType)  # one of the 6 main actions
##   signal cancel_pressed
##   signal confirm_pressed
##   set_button_enabled(action, bool)
##   set_buttons_enabled(bool)                            # toggle all 6
##   set_action_buttons_visible(bool)                     # hide during selection
##   show_prompt(text, allow_skip := false, allow_confirm := false)
##   hide_prompt()

signal action_pressed(action: int)  # CardEnums.ActionType
signal cancel_pressed
signal confirm_pressed

@onready var _btn_play_battle: Button = $Rows/Row1/PlayBattle
@onready var _btn_play_strategy: Button = $Rows/Row1/PlayStrategy
@onready var _btn_gain_rage: Button = $Rows/Row1/GainRage
@onready var _btn_play_monster: Button = $Rows/Row2/PlayMonster
@onready var _btn_invade: Button = $Rows/Row2/Invade
@onready var _btn_end_main: Button = $Rows/Row2/EndMain
@onready var _btn_cancel: Button = $Rows/Row0/Cancel
@onready var _btn_confirm: Button = $Rows/Row0/Confirm
@onready var _prompt_panel: PanelContainer = $PromptPanel
@onready var _prompt_label: Label = $PromptPanel/PromptLabel

var _buttons_by_action: Dictionary = {}


func _ready() -> void:
	_buttons_by_action = {
		CardEnums.ActionType.PLAY_BATTLE: _btn_play_battle,
		CardEnums.ActionType.PLAY_STRATEGY: _btn_play_strategy,
		CardEnums.ActionType.GAIN_RAGE: _btn_gain_rage,
		CardEnums.ActionType.PLAY_MONSTER: _btn_play_monster,
		CardEnums.ActionType.INVADE: _btn_invade,
		CardEnums.ActionType.PASS: _btn_end_main,
	}
	_btn_play_battle.pressed.connect(func(): action_pressed.emit(CardEnums.ActionType.PLAY_BATTLE))
	_btn_play_strategy.pressed.connect(func(): action_pressed.emit(CardEnums.ActionType.PLAY_STRATEGY))
	_btn_gain_rage.pressed.connect(func(): action_pressed.emit(CardEnums.ActionType.GAIN_RAGE))
	_btn_play_monster.pressed.connect(func(): action_pressed.emit(CardEnums.ActionType.PLAY_MONSTER))
	_btn_invade.pressed.connect(func(): action_pressed.emit(CardEnums.ActionType.INVADE))
	_btn_end_main.pressed.connect(func(): action_pressed.emit(CardEnums.ActionType.PASS))
	_btn_cancel.pressed.connect(func(): cancel_pressed.emit())
	_btn_confirm.pressed.connect(func(): confirm_pressed.emit())

	_prompt_panel.visible = false
	_btn_cancel.disabled = true
	_btn_confirm.disabled = true
	set_buttons_enabled(false)


## Enable / disable all 6 main action buttons at once.
func set_buttons_enabled(enabled: bool) -> void:
	for btn in _buttons_by_action.values():
		btn.disabled = not enabled


## Enable / disable one action button.
func set_button_enabled(action: int, enabled: bool) -> void:
	if _buttons_by_action.has(action):
		_buttons_by_action[action].disabled = not enabled


## Hide / show all 6 action button rows (used by overlay flows that take
## over the action area, e.g. the Choice prompt).
func set_action_buttons_visible(vis: bool) -> void:
	$Rows/Row1.visible = vis
	$Rows/Row2.visible = vis


## Show the in-flow prompt with cancel/confirm enabled.
## allow_confirm gates the confirm button. cancel is always enabled.
func show_prompt(text: String, allow_confirm: bool = false) -> void:
	_prompt_label.text = text
	_prompt_panel.visible = true
	_btn_cancel.disabled = false
	_btn_confirm.disabled = not allow_confirm
	set_buttons_enabled(false)


func hide_prompt() -> void:
	_prompt_panel.visible = false
	_btn_cancel.disabled = true
	_btn_confirm.disabled = true


func set_confirm_enabled(enabled: bool) -> void:
	_btn_confirm.disabled = not enabled
