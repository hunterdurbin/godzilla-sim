extends Control

## Replay viewer: renders state snapshots with PlayerBoard.sync_to_state().
## Snapshots are captured per-interaction (every board state change), so
## stepping forward/back shows each card play, draw, etc.

var _replay: ReplayData
var _snapshot_index: int = 0
var _auto_playing: bool = false
var _auto_timer: float = 0.0

var player_board_scene: PackedScene = preload("res://scenes/board/PlayerBoard.tscn")
var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")
var player1_board: Control
var player2_board: Control

# Deserialized player states for current snapshot (used by overlays)
var _player_states: Array = []  # Array of PlayerState

# Hand display
@onready var p1_hand_title: Label = $VBoxContainer/Content/RightPanel/P1HandPanel/P1HandVBox/P1HandTitle
@onready var p1_hand_grid: HBoxContainer = $VBoxContainer/Content/RightPanel/P1HandPanel/P1HandVBox/P1HandScroll/P1HandGrid
@onready var p1_hand_scroll: ScrollContainer = $VBoxContainer/Content/RightPanel/P1HandPanel/P1HandVBox/P1HandScroll
@onready var p2_hand_title: Label = $VBoxContainer/Content/RightPanel/P2HandPanel/P2HandVBox/P2HandTitle
@onready var p2_hand_grid: HBoxContainer = $VBoxContainer/Content/RightPanel/P2HandPanel/P2HandVBox/P2HandScroll/P2HandGrid
@onready var p2_hand_scroll: ScrollContainer = $VBoxContainer/Content/RightPanel/P2HandPanel/P2HandVBox/P2HandScroll

@onready var turn_label: Label = $VBoxContainer/TopBar/TurnLabel
@onready var exit_button: Button = $VBoxContainer/TopBar/ExitButton
@onready var board_column: VBoxContainer = $VBoxContainer/Content/BoardColumn
@onready var log_panel: PanelContainer = $VBoxContainer/Content/RightPanel/LogPanel
@onready var log_output: RichTextLabel = $VBoxContainer/Content/RightPanel/LogPanel/LogVBox/LogOutput
@onready var prev_turn_button: Button = $VBoxContainer/Controls/PrevTurnButton
@onready var prev_button: Button = $VBoxContainer/Controls/PrevButton
@onready var play_pause_button: Button = $VBoxContainer/Controls/PlayPauseButton
@onready var next_button: Button = $VBoxContainer/Controls/NextButton
@onready var next_turn_button: Button = $VBoxContainer/Controls/NextTurnButton
@onready var play_from_here_button: Button = $VBoxContainer/Controls/PlayFromHereButton
@onready var speed_slider: HSlider = $VBoxContainer/Controls/SpeedSlider
@onready var turn_slider: HSlider = $VBoxContainer/Controls/TurnSlider

const PHASE_KEYS := ["STR_RV_PHASE_START", "STR_RV_PHASE_MAIN", "STR_RV_PHASE_COUNTER", "STR_RV_PHASE_END"]

# Card preview (hover)
var _preview_container: Control
var _preview_bg: Panel
var _preview_card: Control

# Card zoom overlay (right-click)
var _zoom_overlay: ColorRect
var _zoom_container: CenterContainer
var _zoom_shown_frame: int = 0

# Gallery overlay (discard, deck, monster deck, zone stack)
var _gallery_overlay: ColorRect
var _gallery_title: Label
var _gallery_grid: GridContainer
var _gallery_stacked_toggle: CheckButton
var _gallery_scroll: ScrollContainer
var _gallery_close_btn: Button
var _gallery_cards: Array[Dictionary] = []

# Controller support
var _pad_hint_row: OverlayHintRow


func _ready() -> void:
	_replay = ReplayData.pending_replay
	ReplayData.pending_replay = null

	GamepadHelper.push_focus_context(self, _default_pad_focus)
	GamepadHelper.gamepad_detected.connect(_wire_pad_mesh)
	GamepadHelper.context_stack_changed.connect(_on_context_stack_changed)
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)

	if not _replay or _replay.snapshots.is_empty():
		turn_label.text = tr("STR_RV_NO_REPLAY_DATA")
		_build_pad_hint_row()
		_wire_pad_mesh()
		return

	# Reset local_player_id so PlayerBoard layouts are correct
	# (may be stale from loading a save as player 2)
	NetworkManager.local_player_id = 0

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
	prev_turn_button.pressed.connect(_on_prev_turn_pressed)
	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	next_turn_button.pressed.connect(_on_next_turn_pressed)
	play_pause_button.pressed.connect(_on_play_pause_pressed)
	play_from_here_button.pressed.connect(_on_play_from_here_pressed)

	# Connect board signals for preview, zoom, and gallery
	_connect_board_signals(player1_board)
	_connect_board_signals(player2_board)

	# Log hover previews
	log_output.meta_underlined = false
	log_output.meta_hover_started.connect(_on_log_meta_hover_started)
	log_output.meta_hover_ended.connect(_on_log_meta_hover_ended)

	# Build overlay UIs
	_build_preview_container()
	_build_zoom_overlay()
	_build_gallery_overlay()

	# Version mismatch warning
	var current_version: String = ProjectSettings.get_setting("application/config/version", "")
	if not _replay.game_version.is_empty() and _replay.game_version != current_version:
		var warning := Label.new()
		warning.text = tr("STR_RV_VERSION_MISMATCH_FMT") % [_replay.game_version, current_version]
		warning.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		warning.add_theme_font_size_override("font_size", 13)
		$VBoxContainer/TopBar.add_child(warning)

	# Set player names for log display
	GameLog.player_names = _replay.player_names.duplicate()

	# Controller hint row — above both overlays (zoom z=200), ctx-driven.
	_build_pad_hint_row()

	# Render first snapshot (meshes the pad focus graph at its end)
	_render_snapshot(0)


func _exit_tree() -> void:
	GamepadHelper.pop_focus_context(self)
	if GamepadHelper.gamepad_detected.is_connected(_wire_pad_mesh):
		GamepadHelper.gamepad_detected.disconnect(_wire_pad_mesh)
	if GamepadHelper.context_stack_changed.is_connected(_on_context_stack_changed):
		GamepadHelper.context_stack_changed.disconnect(_on_context_stack_changed)
	if get_viewport().gui_focus_changed.is_connected(_on_gui_focus_changed):
		get_viewport().gui_focus_changed.disconnect(_on_gui_focus_changed)


func _default_pad_focus() -> Control:
	if not _replay or _replay.snapshots.is_empty():
		return exit_button
	return play_pause_button


func _connect_board_signals(board: Control) -> void:
	board.card_preview_requested.connect(_show_card_preview)
	board.card_preview_cleared.connect(_hide_card_preview)
	board.zone_slot_clicked.connect(_on_zone_clicked)
	board.zone_slot_right_clicked.connect(_on_zone_right_clicked)
	board.strategy_slot_right_clicked.connect(_on_strategy_right_clicked)
	board.discard_clicked.connect(_on_discard_clicked)
	board.deck_clicked.connect(_on_deck_clicked)
	board.monster_deck_clicked.connect(_on_monster_deck_clicked)


func _process(delta: float) -> void:
	if not _auto_playing:
		return
	_auto_timer += delta
	# Slider left=slow, right=fast; invert to get interval
	var interval: float = speed_slider.max_value - speed_slider.value + speed_slider.min_value
	if _auto_timer >= interval:
		_auto_timer = 0.0
		if _snapshot_index < _replay.snapshots.size() - 1:
			_render_snapshot(_snapshot_index + 1)
			turn_slider.set_value_no_signal(float(_snapshot_index))
		else:
			_auto_playing = false
			play_pause_button.text = tr("STR_RV_PLAY")


func _render_snapshot(index: int) -> void:
	_snapshot_index = index
	var snap: Dictionary = _replay.snapshots[index]
	var total_steps: int = _replay.snapshots.size()

	# Build turn label: step N / total — Turn X — Phase — Player
	var turn_num: int = snap.get("turn_number", 0)
	var current_pid: int = snap.get("current_player_id", 0)
	var phase_idx: int = snap.get("phase", 0)
	var phase_name: String = tr(PHASE_KEYS[phase_idx]) if phase_idx < PHASE_KEYS.size() else "?"
	var player_name: String = _replay.player_names[current_pid] if current_pid < _replay.player_names.size() else "?"
	turn_label.text = tr("STR_RV_TURN_LABEL_FMT") % [index + 1, total_steps, turn_num, phase_name, player_name]

	# Indicate final snapshot
	if index == total_steps - 1 and _replay.winner_id >= 0:
		var winner_name: String = _replay.player_names[_replay.winner_id] if _replay.winner_id < _replay.player_names.size() else "?"
		turn_label.text += tr("STR_RV_GAME_OVER_FMT") % winner_name

	# Deserialize player states and sync boards
	var players_data: Array = snap.get("players", [])
	_player_states.clear()
	var pad_focus := _captured_hand_focus()
	if players_data.size() >= 2:
		var ps0 := GameSerializer.deserialize_to_player_state(players_data[0])
		var ps1 := GameSerializer.deserialize_to_player_state(players_data[1])
		_player_states = [ps0, ps1]
		player1_board.reset_visuals()
		player2_board.reset_visuals()
		player1_board.sync_to_state(ps0)
		player2_board.sync_to_state(ps1)

		# Sync hand displays
		var p1_name: String = _replay.player_names[0] if _replay.player_names.size() > 0 else "P1"
		var p2_name: String = _replay.player_names[1] if _replay.player_names.size() > 1 else "P2"
		_sync_hand_display(p1_hand_grid, p1_hand_title, ps0.hand, p1_name)
		_sync_hand_display(p2_hand_grid, p2_hand_title, ps1.hand, p2_name)

		# Highlight active player's hand title
		var active_color := Color(0.9, 0.7, 0.1, 1)
		var inactive_color := Color(0.7, 0.7, 0.7, 1)
		p1_hand_title.add_theme_color_override("font_color", active_color if current_pid == 0 else inactive_color)
		p2_hand_title.add_theme_color_override("font_color", active_color if current_pid == 1 else inactive_color)

	# Display accumulated log lines up to (and including) this snapshot
	log_output.clear()
	for i in range(index + 1):
		var log_lines: Array = _replay.snapshots[i].get("log_lines", [])
		for line in log_lines:
			if typeof(line) == TYPE_DICTIONARY:
				log_output.append_text(GameLog.render(line) + "\n")
			else:
				log_output.append_text(str(line) + "\n")

	# Update button states
	prev_button.disabled = index <= 0
	prev_turn_button.disabled = index <= 0
	next_button.disabled = index >= total_steps - 1
	next_turn_button.disabled = index >= total_steps - 1
	play_from_here_button.disabled = not snap.get("is_boundary", false)

	# The hand rows were rebuilt — re-mesh and put the pad cursor back.
	_wire_pad_mesh()
	_restore_hand_focus(pad_focus)


# --- Hand display ---

func _sync_hand_display(grid: HBoxContainer, title: Label, hand_cards: Array, player_name: String) -> void:
	# Clear existing cards
	for child in grid.get_children():
		child.queue_free()

	title.text = tr("STR_RV_HAND_TITLE_FMT") % [player_name, hand_cards.size()]

	for card_data in hand_cards:
		var card: Control = card_scene.instantiate()
		card.set_card_data_dict(card_data)
		card.drag_enabled = false
		card.is_selectable = false
		card.hover_scale = 1.0
		card.hover_lift = 0.0
		card.custom_minimum_size = Vector2(80, 112)
		card.card_right_clicked.connect(_on_hand_card_right_clicked)
		card.card_hover_started.connect(_on_hand_card_hover_started)
		card.card_hover_ended.connect(_on_hand_card_hover_ended)
		grid.add_child(card)
		# Pad focus mirrors hover: preview + keep the card in view. Y zooms
		# via card.gd's focused pad_inspect → card_right_clicked path.
		GamepadHelper.make_pad_focusable(card)
		card.focus_entered.connect(_on_hand_card_focus_entered.bind(card, grid))
		card.focus_exited.connect(_on_hand_card_hover_ended.bind(card))


func _on_hand_card_focus_entered(card: Control, grid: HBoxContainer) -> void:
	var scroll := p1_hand_scroll if grid == p1_hand_grid else p2_hand_scroll
	scroll.ensure_control_visible(card)
	_on_hand_card_hover_started(card)


func _on_hand_card_right_clicked(card: Control) -> void:
	if "card_data" in card and not card.card_data.is_empty():
		_show_card_zoom(card.card_data)


func _on_hand_card_hover_started(card: Control) -> void:
	if "card_data" in card and not card.card_data.is_empty():
		_show_card_preview(card.card_data)


func _on_hand_card_hover_ended(_card: Control) -> void:
	_hide_card_preview()


# --- Card preview (hover) ---

func _build_preview_container() -> void:
	_preview_container = Control.new()
	_preview_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_container.z_index = 50
	_preview_container.visible = false
	log_panel.add_child(_preview_container)

	_preview_bg = Panel.new()
	_preview_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	bg_style.corner_radius_top_left = 8
	bg_style.corner_radius_top_right = 8
	bg_style.corner_radius_bottom_left = 8
	bg_style.corner_radius_bottom_right = 8
	_preview_bg.add_theme_stylebox_override("panel", bg_style)
	_preview_container.add_child(_preview_bg)

	_preview_card = card_scene.instantiate()
	_preview_card.drag_enabled = false
	_preview_card.hover_scale = 1.0
	_preview_card.hover_lift = 0.0
	_preview_container.add_child(_preview_card)
	_set_mouse_filter_ignore_recursive(_preview_card)


func _show_card_preview(data: Dictionary, _play_cost_modifier: int = 0, _power_preview: int = 0) -> void:
	if data.is_empty():
		return
	_preview_card.set_card_data_dict(data)
	var is_strategy: bool = data.get("card_type", -1) == CardEnums.CardType.STRATEGY
	if is_strategy:
		_show_strategy_preview()
	else:
		_show_normal_preview()


func _show_normal_preview() -> void:
	# Center the card within the log panel area
	var container_size := _preview_container.size
	var card_ratio := 5.0 / 7.0
	var margin := 12.0
	var card_w := container_size.x - margin * 2
	var card_h := card_w / card_ratio
	if card_h > container_size.y - margin * 2:
		card_h = container_size.y - margin * 2
		card_w = card_h * card_ratio
	var card_pos := Vector2(
		(container_size.x - card_w) / 2.0,
		(container_size.y - card_h) / 2.0
	)
	var padding := 6.0
	_preview_bg.position = card_pos - Vector2(padding, padding)
	_preview_bg.size = Vector2(card_w, card_h) + Vector2(padding * 2, padding * 2)
	_preview_card.size = Vector2(card_w, card_h)
	_preview_card.position = card_pos
	_preview_card.pivot_offset = Vector2(card_w, card_h) / 2.0
	_preview_card.scale = Vector2.ONE
	_preview_card.rotation = 0.0
	_preview_container.visible = true


func _show_strategy_preview() -> void:
	# Center the rotated strategy card within the log panel area
	var container_size := _preview_container.size
	var card_ratio := 5.0 / 7.0
	var margin := 12.0
	# Rotated -90: visual_w = card_h, visual_h = card_w
	var visual_w := container_size.x - margin * 2
	var card_h := visual_w  # un-rotated height = visual width
	var card_w := card_h * card_ratio  # un-rotated width
	var visual_h := card_w
	if visual_h > container_size.y - margin * 2:
		visual_h = container_size.y - margin * 2
		card_w = visual_h
		card_h = card_w / card_ratio
		visual_w = card_h
	var card_pos := Vector2(
		(container_size.x - visual_w) / 2.0,
		(container_size.y - visual_h) / 2.0
	)
	_preview_card.size = Vector2(card_w, card_h)
	_preview_card.pivot_offset = Vector2(card_w, card_h) / 2.0
	_preview_card.rotation = -PI / 2.0
	_preview_card.scale = Vector2.ONE
	_preview_card.position = card_pos + Vector2((visual_w - card_w) / 2.0, (visual_h - card_h) / 2.0)
	var padding := 6.0
	_preview_bg.position = card_pos - Vector2(padding, padding)
	_preview_bg.size = Vector2(visual_w, visual_h) + Vector2(padding * 2, padding * 2)
	_preview_container.visible = true


func _hide_card_preview() -> void:
	if _preview_container:
		_preview_container.visible = false


# --- Card zoom overlay (right-click) ---

func _build_zoom_overlay() -> void:
	_zoom_overlay = ColorRect.new()
	_zoom_overlay.color = Color(0, 0, 0, 0.7)
	_zoom_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_zoom_overlay.z_index = 200
	_zoom_overlay.visible = false
	_zoom_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_zoom_overlay)

	_zoom_container = CenterContainer.new()
	_zoom_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_zoom_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_zoom_overlay.add_child(_zoom_container)

	# Focus context only — nothing focusable inside; focus stays on the
	# control behind the dim, so _input swallows the pad twins while visible.
	GamepadHelper.register_modal(_zoom_overlay, func() -> Control: return null)


func _show_card_zoom(card_data: Dictionary) -> void:
	for child in _zoom_container.get_children():
		child.queue_free()

	var card: Control = card_scene.instantiate()
	card.set_card_data_dict(card_data)
	card.is_selectable = false
	card.drag_enabled = false
	card.hover_scale = 1.0
	card.hover_lift = 0.0
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var is_strategy: bool = card_data.get("card_type") == CardEnums.CardType.STRATEGY
	if is_strategy:
		var portrait_size := Vector2(405, 567)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(portrait_size.y, portrait_size.x)  # 567x405
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_zoom_container.add_child(wrapper)
		card.custom_minimum_size = Vector2.ZERO
		card.size = portrait_size
		card.pivot_offset = portrait_size / 2.0
		card.rotation = deg_to_rad(-90)
		card.position = Vector2(
			(wrapper.custom_minimum_size.x - portrait_size.x) / 2.0,
			(wrapper.custom_minimum_size.y - portrait_size.y) / 2.0
		)
		wrapper.add_child(card)
	else:
		card.custom_minimum_size = Vector2(405, 567)
		_zoom_container.add_child(card)

	_zoom_overlay.visible = true
	_zoom_shown_frame = Engine.get_process_frames()


func _hide_card_zoom() -> void:
	_zoom_overlay.visible = false
	for child in _zoom_container.get_children():
		child.queue_free()


# --- Gallery overlay (discard, deck, monster deck, zone stack) ---

func _build_gallery_overlay() -> void:
	_gallery_overlay = ColorRect.new()
	_gallery_overlay.color = Color(0, 0, 0, 0.6)
	_gallery_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gallery_overlay.z_index = 100
	_gallery_overlay.visible = false
	_gallery_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_gallery_overlay.gui_input.connect(_on_gallery_overlay_input)
	add_child(_gallery_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_gallery_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 0)
	# Set max height to 75% viewport via anchors on the center container
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	# Title row with stacked toggle
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	_gallery_title = Label.new()
	_gallery_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gallery_title.add_theme_font_size_override("font_size", 18)
	_gallery_title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	title_row.add_child(_gallery_title)

	_gallery_stacked_toggle = CheckButton.new()
	_gallery_stacked_toggle.text = tr("STR_RV_STACKED")
	_gallery_stacked_toggle.add_theme_font_size_override("font_size", 13)
	_gallery_stacked_toggle.toggled.connect(_on_gallery_stacked_toggled)
	title_row.add_child(_gallery_stacked_toggle)

	# Scrollable grid
	_gallery_scroll = ScrollContainer.new()
	_gallery_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_gallery_scroll.custom_minimum_size = Vector2(0, 400)
	vbox.add_child(_gallery_scroll)

	_gallery_grid = GridContainer.new()
	_gallery_grid.columns = 4
	_gallery_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gallery_grid.add_theme_constant_override("h_separation", 8)
	_gallery_grid.add_theme_constant_override("v_separation", 8)
	_gallery_scroll.add_child(_gallery_grid)

	# Close button
	_gallery_close_btn = Button.new()
	_gallery_close_btn.text = tr("STR_RV_CLOSE")
	_gallery_close_btn.custom_minimum_size = Vector2(100, 36)
	_gallery_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_gallery_close_btn.pressed.connect(_hide_gallery)
	vbox.add_child(_gallery_close_btn)

	# Chrome joins the pad mesh but must not show mouse focus rings.
	GamepadHelper.make_pad_focusable(_gallery_stacked_toggle)
	GamepadHelper.make_pad_focusable(_gallery_close_btn)
	GamepadHelper.register_modal(_gallery_overlay, _gallery_pad_provider)


func _show_gallery(title: String, cards: Array, show_stacked: bool = true) -> void:
	_gallery_cards.clear()
	for c in cards:
		_gallery_cards.append(c)
	_gallery_title.text = tr("STR_RV_GALLERY_TITLE_FMT") % [title, cards.size()]
	_gallery_stacked_toggle.visible = show_stacked
	_gallery_stacked_toggle.set_pressed_no_signal(false)
	_gallery_overlay.visible = true
	_refresh_gallery_grid()


func _hide_gallery() -> void:
	_gallery_overlay.visible = false
	for child in _gallery_grid.get_children():
		child.queue_free()
	_gallery_cards.clear()


func _refresh_gallery_grid() -> void:
	# The cards are freed on every refresh — capture the pad spot first.
	var pad_idx := OverlayGridUtil.focused_index(_gallery_grid)
	for child in _gallery_grid.get_children():
		child.queue_free()

	if _gallery_cards.is_empty():
		var empty_label := Label.new()
		empty_label.text = tr("STR_RV_NO_CARDS")
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_gallery_grid.add_child(empty_label)
		_wire_gallery_pad()
		return

	var stacked := _gallery_stacked_toggle.button_pressed
	if stacked:
		var groups := _group_cards(_gallery_cards)
		for group in groups:
			var card: Control = card_scene.instantiate()
			card.set_card_data_dict(group["card_data"])
			card.is_selectable = false
			card.drag_enabled = false
			_set_gallery_hover(card)
			card.card_right_clicked.connect(_on_gallery_card_right_clicked)
			_gallery_grid.add_child(card)
			_add_count_badge(card, group["count"])
	else:
		for card_data in _gallery_cards:
			var card: Control = card_scene.instantiate()
			card.set_card_data_dict(card_data)
			card.is_selectable = false
			card.drag_enabled = false
			_set_gallery_hover(card)
			card.card_right_clicked.connect(_on_gallery_card_right_clicked)
			_gallery_grid.add_child(card)

	_wire_gallery_pad()
	if pad_idx >= 0:
		OverlayGridUtil.focus_index(_gallery_grid, pad_idx, _gallery_close_btn)


func _on_gallery_overlay_input(event: InputEvent) -> void:
	# Clicks on the dark area outside the panel dismiss the gallery
	if event is InputEventMouseButton and event.pressed:
		_hide_gallery()
		get_viewport().set_input_as_handled()


func _on_gallery_stacked_toggled(_value: bool) -> void:
	_refresh_gallery_grid()


func _on_gallery_card_right_clicked(card: Control) -> void:
	if "card_data" in card and not card.card_data.is_empty():
		_show_card_zoom(card.card_data)


func _set_gallery_hover(card: Control) -> void:
	card.hover_scale = 1.05
	card.hover_lift = 0.0
	card.gui_input.connect(_on_gallery_card_input.bind(card))


func _on_gallery_card_input(event: InputEvent, card: Control) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if "card_data" in card and not card.card_data.is_empty():
			_show_card_zoom(card.card_data)


func _group_cards(cards: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Dictionary = {}
	var order: Array[String] = []
	for card_data in cards:
		var tid := _get_card_template_id(card_data)
		if groups.has(tid):
			groups[tid]["count"] += 1
		else:
			groups[tid] = {"card_data": card_data, "count": 1}
			order.append(tid)
	var result: Array[Dictionary] = []
	for tid in order:
		result.append(groups[tid])
	return result


func _get_card_template_id(card_data: Dictionary) -> String:
	var id: String = card_data.get("id", "")
	var parts := id.split("_")
	return parts[0] if not parts.is_empty() else id


func _add_count_badge(card: Control, count: int) -> void:
	if count <= 1:
		return
	var badge := Label.new()
	badge.text = "x%d" % count
	badge.add_theme_font_size_override("font_size", 16)
	badge.add_theme_color_override("font_color", Color.YELLOW)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -40
	badge.offset_right = -4
	badge.offset_top = 10
	card.add_child(badge)


# --- Board signal handlers ---

func _on_zone_clicked(zone_num: int, pid: int) -> void:
	if pid < _player_states.size():
		var state: PlayerState = _player_states[pid]
		var zone_idx := zone_num - 1
		var stack: Array = state.get_zone_stack(zone_idx)
		if stack.size() > 1:
			var pname: String = _replay.player_names[pid] if pid < _replay.player_names.size() else "P%d" % (pid + 1)
			_show_gallery(tr("STR_RV_ZONE_STACK_TITLE_FMT") % [pname, zone_num], stack, false)
		elif stack.size() == 1:
			_show_card_zoom(stack[0])
		else:
			if state.monster_zone == zone_num and not state.current_monster.is_empty():
				_show_card_zoom(state.current_monster)


func _on_zone_right_clicked(zone_num: int, pid: int) -> void:
	if pid < _player_states.size():
		var state: PlayerState = _player_states[pid]
		var zone_idx := zone_num - 1
		var stack: Array = state.get_zone_stack(zone_idx)
		if stack.size() > 1:
			var pname: String = _replay.player_names[pid] if pid < _replay.player_names.size() else "P%d" % (pid + 1)
			_show_gallery(tr("STR_RV_ZONE_STACK_TITLE_FMT") % [pname, zone_num], stack, false)
		elif stack.size() == 1:
			_show_card_zoom(stack[0])
		else:
			# Check if monster is in this zone
			if state.monster_zone == zone_num and not state.current_monster.is_empty():
				_show_card_zoom(state.current_monster)


func _on_strategy_right_clicked(strategy_idx: int, pid: int) -> void:
	if pid < _player_states.size():
		var state: PlayerState = _player_states[pid]
		if strategy_idx < state.strategy_zones.size():
			var card_data: Dictionary = state.strategy_zones[strategy_idx]
			if not card_data.is_empty():
				_show_card_zoom(card_data)


func _on_discard_clicked(pid: int) -> void:
	if pid < _player_states.size():
		var state: PlayerState = _player_states[pid]
		var cards: Array[Dictionary] = state.discard_pile.duplicate(true)
		cards.reverse()
		var pname: String = _replay.player_names[pid] if pid < _replay.player_names.size() else "P%d" % (pid + 1)
		_show_gallery(tr("STR_RV_DISCARD_TITLE_FMT") % pname, cards)


func _on_deck_clicked(pid: int) -> void:
	if pid < _player_states.size():
		var state: PlayerState = _player_states[pid]
		var pname: String = _replay.player_names[pid] if pid < _replay.player_names.size() else "P%d" % (pid + 1)
		_show_gallery(tr("STR_RV_MAIN_DECK_TITLE_FMT") % pname, state.main_deck.duplicate(true))


func _on_monster_deck_clicked(pid: int) -> void:
	if pid < _player_states.size():
		var state: PlayerState = _player_states[pid]
		var pname: String = _replay.player_names[pid] if pid < _replay.player_names.size() else "P%d" % (pid + 1)
		_show_gallery(tr("STR_RV_MONSTER_DECK_TITLE_FMT") % pname, state.monster_deck.duplicate(true))


# --- Log hover ---

func _on_log_meta_hover_started(meta: Variant) -> void:
	var card_id: String = str(meta)
	var data: Dictionary = CardData.get_card_by_id(card_id)
	if not data.is_empty():
		_show_card_preview(data)


func _on_log_meta_hover_ended(_meta: Variant) -> void:
	_hide_card_preview()


# --- Input handling (Escape dismissal) ---

func _input(event: InputEvent) -> void:
	# Zoom overlay: any click, pad B, or Escape dismisses (gui_input can't
	# reach the overlay because card's internal children consume mouse events)
	if _zoom_overlay and _zoom_overlay.visible:
		if GamepadHelper.is_cancel_press(event):
			# Act on the LEADING pad_cancel; the mirrored twins are swallowed
			# so they can't fall through to the gallery/back handlers below.
			if not GamepadHelper.is_swallowed_cancel(event):
				GamepadHelper.swallow_cancel_twins()
				_hide_card_zoom()
			get_viewport().set_input_as_handled()
			return
		# The control behind the dim (hand/gallery card) still holds real
		# focus: swallow the injected pad twins so the mirrored ui_* can't
		# crawl its mesh under the zoom (card_zoom_overlay does the same).
		if event is InputEventAction and event.pressed and event.action in [
				&"pad_nav_up", &"pad_nav_down", &"pad_nav_left", &"pad_nav_right",
				&"ui_up", &"ui_down", &"ui_left", &"ui_right",
				&"ui_accept", &"pad_confirm", &"pad_inspect", &"pad_end_main"]:
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed:
			if (Engine.get_process_frames() - _zoom_shown_frame) > 2:
				_hide_card_zoom()
				get_viewport().set_input_as_handled()
			return

	# Gallery overlay: pad B / Escape dismisses
	if _gallery_overlay and _gallery_overlay.visible:
		if GamepadHelper.is_cancel_press(event):
			if not GamepadHelper.is_swallowed_cancel(event):
				GamepadHelper.swallow_cancel_twins()
				_hide_gallery()
			get_viewport().set_input_as_handled()
			return

	# Keyboard shortcuts for navigation
	if not _replay or _replay.snapshots.is_empty():
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_RIGHT:
				if event.shift_pressed:
					_on_next_turn_pressed()
				else:
					_on_next_pressed()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				if event.shift_pressed:
					_on_prev_turn_pressed()
				else:
					_on_prev_pressed()
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				if not event.echo:
					_on_play_pause_pressed()
				get_viewport().set_input_as_handled()
			KEY_UP:
				speed_slider.value = minf(speed_slider.max_value, speed_slider.value + speed_slider.step)
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				speed_slider.value = maxf(speed_slider.min_value, speed_slider.value - speed_slider.step)
				get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Pad B (leading pad_cancel) / Escape at screen level exits to Extras.
	# The overlay dismissals in _input mark their press handled and swallow
	# the twins, so this only fires bare.
	if event.is_action_pressed("pad_cancel") or event.is_action_pressed("ui_cancel"):
		if GamepadHelper.is_swallowed_cancel(event):
			get_viewport().set_input_as_handled()
			return
		if not GamepadHelper.is_top_context(self):
			return
		get_viewport().set_input_as_handled()
		GamepadHelper.swallow_cancel_twins()
		_on_exit_pressed()
		return
	if not _replay or _replay.snapshots.is_empty() \
			or not GamepadHelper.is_top_context(self):
		return
	# Bumpers step one snapshot (LB back, RB forward); triggers jump a whole
	# turn (LT back, RT forward) — the pad twin of the transport buttons.
	if event.is_action_pressed("pad_focus_log"):
		get_viewport().set_input_as_handled()
		_on_prev_pressed()
	elif event.is_action_pressed("pad_focus_tracker"):
		get_viewport().set_input_as_handled()
		_on_next_pressed()
	elif event.is_action_pressed("pad_play_card_rage"):
		get_viewport().set_input_as_handled()
		_on_prev_turn_pressed()
	elif event.is_action_pressed("pad_play_card_invasion"):
		get_viewport().set_input_as_handled()
		_on_next_turn_pressed()


# --- Controller support ---

## Focus mesh over the static chrome and the (rebuilt-per-snapshot) hand
## rows. Sliders consume ←/→ for their value, so each gets its OWN band —
## sharing the transport row would make everything right of a slider
## unreachable (↑/↓ is the only way off one).
func _wire_pad_mesh() -> void:
	if not GamepadHelper.is_using_gamepad():
		return
	OverlayGridUtil.wire_band_stack([
		{"row": [exit_button] as Array[Control]},
		{"row": _hand_cards(p2_hand_grid)},
		{"row": _hand_cards(p1_hand_grid)},
		{"row": [prev_turn_button, prev_button, play_pause_button, next_button,
				next_turn_button, play_from_here_button] as Array[Control]},
		{"row": [speed_slider] as Array[Control]},
		{"row": [turn_slider] as Array[Control]},
	])
	# A gallery opened with the mouse must become walkable after a mid-session
	# flip to pad (gamepad_detected routes here).
	if _gallery_overlay != null and _gallery_overlay.visible:
		_wire_gallery_pad()


func _hand_cards(grid: HBoxContainer) -> Array[Control]:
	var cards: Array[Control] = []
	for child in grid.get_children():
		if child is Control and not child.is_queued_for_deletion():
			cards.append(child)
	return cards


## (grid, index) of the pad focus if it sits in a hand row — the card nodes
## are freed on every snapshot render, so remember the position, not the node.
func _captured_hand_focus() -> Dictionary:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null:
		return {}
	for grid in [p1_hand_grid, p2_hand_grid]:
		var idx := _hand_cards(grid).find(focus_owner)
		if idx >= 0:
			return {"grid": grid, "index": idx}
	return {}


func _restore_hand_focus(captured: Dictionary) -> void:
	if captured.is_empty() or not GamepadHelper.is_using_gamepad():
		return
	(func() -> void:
		var cards := _hand_cards(captured["grid"])
		if cards.is_empty():
			# Hand emptied — fall back to the transport row.
			if play_pause_button.is_visible_in_tree():
				play_pause_button.grab_focus()
			return
		cards[clampi(int(captured["index"]), 0, cards.size() - 1)].grab_focus()
	).call_deferred()


func _gallery_pad_provider() -> Control:
	var cards := OverlayGridUtil.grid_cards(_gallery_grid)
	if not cards.is_empty():
		return cards[0]
	return _gallery_close_btn


func _wire_gallery_pad() -> void:
	if not GamepadHelper.is_using_gamepad():
		return
	OverlayGridUtil.wire_overlay_focus(_gallery_grid,
			[_gallery_stacked_toggle] as Array[Control],
			[_gallery_close_btn] as Array[Control])
	for card in OverlayGridUtil.grid_cards(_gallery_grid):
		if not card.focus_entered.is_connected(_on_gallery_card_focus_entered):
			card.focus_entered.connect(_on_gallery_card_focus_entered.bind(card))


func _on_gallery_card_focus_entered(card: Control) -> void:
	_gallery_scroll.ensure_control_visible(card)


func _build_pad_hint_row() -> void:
	_pad_hint_row = OverlayHintRow.new()
	_pad_hint_row.z_index = 250
	add_child(_pad_hint_row)
	# Margin 56 clears the transport row that spans the bottom edge.
	_pad_hint_row.set_anchors_and_offsets_preset(
			Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 56)
	_pad_hint_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pad_hint_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_refresh_pad_hints()


func _on_gui_focus_changed(_control: Control) -> void:
	_refresh_pad_hints()


func _on_context_stack_changed() -> void:
	# The zoom/gallery contexts are ours (the row floats above them and
	# describes them); any other modal on top hides the row until it closes.
	if _pad_hint_row == null:
		return
	if not GamepadHelper.is_top_context(self) and _overlay_ctx().is_empty():
		_pad_hint_row.visible = false
	else:
		_refresh_pad_hints()


func _overlay_ctx() -> String:
	if _zoom_overlay != null and _zoom_overlay.visible:
		return "zoom"
	if _gallery_overlay != null and _gallery_overlay.visible:
		return "gallery"
	return ""


func _refresh_pad_hints() -> void:
	if _pad_hint_row == null:
		return
	var ctx := {"overlay": _overlay_ctx(), "area": "chrome"}
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		if focus_owner.get_parent() == p1_hand_grid \
				or focus_owner.get_parent() == p2_hand_grid:
			ctx["area"] = "card"
		elif focus_owner is HSlider:
			ctx["area"] = "slider"
	var hints: Array[Dictionary] = []
	for h in ReplayViewerPadHints.compute(ctx):
		var hint := {"action": h["action"], "text": tr(h["text_key"])}
		if h.has("action2"):
			hint["action2"] = h["action2"]
		hints.append(hint)
	_pad_hint_row.set_hints(hints)


# --- Helpers ---

func _set_mouse_filter_ignore_recursive(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_set_mouse_filter_ignore_recursive(child)


# --- Navigation ---

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


func _on_prev_turn_pressed() -> void:
	SfxManager.play("ui_click")
	if _snapshot_index <= 0:
		return
	var current_turn: int = _replay.snapshots[_snapshot_index].get("turn_number", 0)
	# Walk backward to find the first snapshot of the previous turn
	var target := _snapshot_index - 1
	while target > 0 and _replay.snapshots[target].get("turn_number", 0) == current_turn:
		target -= 1
	_render_snapshot(target)
	turn_slider.set_value_no_signal(float(_snapshot_index))


func _on_next_turn_pressed() -> void:
	SfxManager.play("ui_click")
	var max_idx: int = _replay.snapshots.size() - 1
	if _snapshot_index >= max_idx:
		return
	var current_turn: int = _replay.snapshots[_snapshot_index].get("turn_number", 0)
	# Walk forward to find the first snapshot of the next turn
	var target := _snapshot_index + 1
	while target < max_idx and _replay.snapshots[target].get("turn_number", 0) == current_turn:
		target += 1
	_render_snapshot(target)
	turn_slider.set_value_no_signal(float(_snapshot_index))


func _on_play_pause_pressed() -> void:
	SfxManager.play("ui_click")
	_auto_playing = not _auto_playing
	play_pause_button.text = tr("STR_RV_PAUSE") if _auto_playing else tr("STR_RV_PLAY")
	_auto_timer = 0.0


func _on_turn_slider_changed(value: float) -> void:
	var idx := int(value)
	if idx != _snapshot_index:
		_render_snapshot(idx)


func _on_play_from_here_pressed() -> void:
	SfxManager.play("ui_click")
	var snap: Dictionary = _replay.snapshots[_snapshot_index]
	# Build a save-compatible dict from the current snapshot + replay metadata
	GameSerializer.pending_load = {
		"version": 1,
		"turn_number": snap.get("turn_number", 1),
		"current_player_id": snap.get("current_player_id", 0),
		"current_phase": snap.get("phase", 0),
		"current_sub_phase": snap.get("sub_phase", 0),
		"player_names": Array(_replay.player_names),
		"first_player_id": _replay.first_player_id,
		"mode": "solo",
		"bot_difficulty": "",
		"deck_names": Array(_replay.deck_names),
		"game_seed": _replay.game_seed,
		"players": snap.get("players", []),
	}
	NetworkManager.mode = NetworkManager.Mode.SOLO
	NetworkManager.local_player_id = 0
	NetworkManager.change_scene("res://scenes/board/GameBoard.tscn")


func _on_exit_pressed() -> void:
	SfxManager.play("ui_click")
	NetworkManager.change_scene("res://scenes/menus/Extras.tscn")
