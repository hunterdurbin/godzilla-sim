extends Control

## Replay viewer: renders per-turn state snapshots with PlayerBoard.sync_to_state().
## No game logic — just visual rendering of captured snapshots.

var _replay: ReplayData
var _snapshot_index: int = 0
var _auto_playing: bool = false
var _auto_timer: float = 0.0

var player_board_scene: PackedScene = preload("res://scenes/board/PlayerBoard.tscn")
var player1_board: Control
var player2_board: Control

@onready var turn_label: Label = $VBoxContainer/TopBar/TurnLabel
@onready var exit_button: Button = $VBoxContainer/TopBar/ExitButton
@onready var board_column: VBoxContainer = $VBoxContainer/Content/BoardColumn
@onready var log_output: RichTextLabel = $VBoxContainer/Content/LogPanel/LogVBox/LogOutput
@onready var prev_button: Button = $VBoxContainer/Controls/PrevButton
@onready var play_pause_button: Button = $VBoxContainer/Controls/PlayPauseButton
@onready var next_button: Button = $VBoxContainer/Controls/NextButton
@onready var speed_slider: HSlider = $VBoxContainer/Controls/SpeedSlider
@onready var turn_slider: HSlider = $VBoxContainer/Controls/TurnSlider


func _ready() -> void:
	_replay = ReplayData.pending_replay
	ReplayData.pending_replay = null

	if not _replay or _replay.snapshots.is_empty():
		turn_label.text = "No replay data"
		return

	# Create player boards
	player2_board = player_board_scene.instantiate()
	player2_board.player_id = 1
	player2_board.is_mirrored = true
	player2_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_column.add_child(player2_board)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 2)
	divider.color = Color(0.5, 0.5, 0.6, 0.8)
	board_column.add_child(divider)

	player1_board = player_board_scene.instantiate()
	player1_board.player_id = 0
	player1_board.is_mirrored = false
	player1_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_column.add_child(player1_board)

	# Set up turn slider
	turn_slider.max_value = _replay.snapshots.size() - 1
	turn_slider.value = 0
	turn_slider.value_changed.connect(_on_turn_slider_changed)

	# Connect controls
	exit_button.pressed.connect(_on_exit_pressed)
	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	play_pause_button.pressed.connect(_on_play_pause_pressed)

	# Set player names for log display
	GameLog.player_names = _replay.player_names.duplicate()

	# Render first snapshot
	_render_snapshot(0)


func _process(delta: float) -> void:
	if not _auto_playing:
		return
	_auto_timer += delta
	var interval: float = speed_slider.value
	if _auto_timer >= interval:
		_auto_timer = 0.0
		if _snapshot_index < _replay.snapshots.size() - 1:
			_render_snapshot(_snapshot_index + 1)
			turn_slider.set_value_no_signal(float(_snapshot_index))
		else:
			_auto_playing = false
			play_pause_button.text = "Play"


func _render_snapshot(index: int) -> void:
	_snapshot_index = index
	var snap: Dictionary = _replay.snapshots[index]

	# Update turn label
	var turn_num: int = snap.get("turn_number", 0)
	var current_pid: int = snap.get("current_player_id", 0)
	var max_turns: int = _replay.total_turns
	var player_name: String = _replay.player_names[current_pid] if current_pid < _replay.player_names.size() else "?"
	turn_label.text = "Turn %d/%d — %s" % [turn_num, max_turns, player_name]

	# Indicate final snapshot
	if index == _replay.snapshots.size() - 1 and _replay.winner_id >= 0:
		var winner_name: String = _replay.player_names[_replay.winner_id] if _replay.winner_id < _replay.player_names.size() else "?"
		turn_label.text += "  [GAME OVER — %s wins]" % winner_name

	# Deserialize player states and sync boards
	var players_data: Array = snap.get("players", [])
	if players_data.size() >= 2:
		var ps0 := GameSerializer.deserialize_to_player_state(players_data[0])
		var ps1 := GameSerializer.deserialize_to_player_state(players_data[1])
		player1_board.reset_visuals()
		player2_board.reset_visuals()
		player1_board.sync_to_state(ps0)
		player2_board.sync_to_state(ps1)

	# Display log lines
	log_output.clear()
	var log_lines: Array = snap.get("log_lines", [])
	for line in log_lines:
		log_output.append_text(str(line) + "\n")

	# Update button states
	prev_button.disabled = index <= 0
	next_button.disabled = index >= _replay.snapshots.size() - 1


func _on_prev_pressed() -> void:
	SfxManager.play("ui_click")
	if _snapshot_index > 0:
		_render_snapshot(_snapshot_index - 1)
		turn_slider.set_value_no_signal(float(_snapshot_index))


func _on_next_pressed() -> void:
	SfxManager.play("ui_click")
	if _snapshot_index < _replay.snapshots.size() - 1:
		_render_snapshot(_snapshot_index + 1)
		turn_slider.set_value_no_signal(float(_snapshot_index))


func _on_play_pause_pressed() -> void:
	SfxManager.play("ui_click")
	_auto_playing = not _auto_playing
	play_pause_button.text = "Pause" if _auto_playing else "Play"
	_auto_timer = 0.0


func _on_turn_slider_changed(value: float) -> void:
	var idx := int(value)
	if idx != _snapshot_index:
		_render_snapshot(idx)


func _on_exit_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/ui/Extras.tscn")
