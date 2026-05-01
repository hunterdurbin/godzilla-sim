extends PanelContainer

## Drop-in game-log panel. Auto-binds to session.turn_manager.log_message
## and session.effect_handler.log_message, renders the token stream into
## the embedded RichTextLabel via GameLog.render().
##
## To use: drop into your scene tree under the GameBoard root. No script
## changes needed.

@export var max_lines: int = 200

var _session: GameSession = null

@onready var _output: RichTextLabel = $VBox/ScrollContainer/LogOutput


func _ready() -> void:
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_try_bind()


func _try_bind() -> void:
	_session = BoardModule.find_session(self)
	if _session == null:
		return
	if _session.is_running():
		_bind()
	else:
		_session.session_started.connect(_bind, CONNECT_ONE_SHOT)


func _bind() -> void:
	if _session == null or _session.turn_manager == null:
		return
	_session.turn_manager.log_message.connect(_on_log_message)
	if _session.effect_handler:
		_session.effect_handler.log_message.connect(_on_log_message)
	_session.turn_manager.game_ended.connect(_on_game_ended)


func _on_log_message(token) -> void:
	var rendered: String
	if token is Dictionary:
		rendered = GameLog.render(token)
	else:
		rendered = str(token)
	_output.append_text(rendered + "\n")
	# Cap the buffer so very long games don't blow memory.
	if max_lines > 0 and _output.get_line_count() > max_lines:
		_output.text = _output.text.split("\n", false).slice(-max_lines).reduce(func(acc, s): return acc + s + "\n", "")


func _on_game_ended(winner_id: int, reason_key: String) -> void:
	var reason := GameLog.render_reason(reason_key)
	_output.append_text("\n[color=yellow]%s[/color]: %s\n%s\n" % [
		tr("STR_GB_GAME_OVER"),
		tr("STR_GB_WINS_FMT").replace("{NAME}", GameLog.player_name(winner_id)),
		reason,
	])
