extends PanelContainer

## Drop-in end-of-game panel. Auto-binds to session.turn_manager.game_ended,
## shows winner + reason, exposes Rematch and Main Menu buttons.
##
## Subclass and override `_on_rematch_pressed` if you want to drive a
## custom rematch flow (deck-select, re-bot-seed, etc.). The default
## emits the `rematch_pressed` signal — host scene can listen.

signal rematch_pressed
signal menu_pressed

@onready var _win_label: Label = $VBox/WinLabel
@onready var _btn_rematch: Button = $VBox/ButtonRow/RematchButton
@onready var _btn_menu: Button = $VBox/ButtonRow/MenuButton


func _ready() -> void:
	visible = false
	z_index = 100
	_btn_rematch.pressed.connect(_on_rematch_pressed)
	_btn_menu.pressed.connect(_on_menu_pressed)
	_try_bind()


func _try_bind() -> void:
	var session := BoardModule.find_session(self)
	if session == null:
		return
	if session.is_running():
		_bind(session)
	else:
		session.session_started.connect(func(): _bind(session), CONNECT_ONE_SHOT)


func _bind(session: GameSession) -> void:
	if session.turn_manager:
		session.turn_manager.game_ended.connect(_on_game_ended)


func _on_game_ended(winner_id: int, reason_key: String) -> void:
	var session := BoardModule.find_session(self)
	var winner_name := GameLog.player_name(winner_id) if session else str(winner_id)
	var reason := GameLog.render_reason(reason_key)
	_win_label.text = tr("STR_GB_WINS_FMT").replace("{NAME}", winner_name) + "\n" + reason
	visible = true


func _on_rematch_pressed() -> void:
	rematch_pressed.emit()


func _on_menu_pressed() -> void:
	NetworkManager.is_in_game = false
	menu_pressed.emit()
	NetworkManager.change_scene("res://scenes/ui/MainMenu.tscn")
