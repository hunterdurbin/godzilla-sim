class_name MobileLayout
extends Node

## Mobile presentation concern: runtime restyling of the desktop GameBoard
## into the phone layout — circle/pill button styles, the FAB action button
## system, the log/CP/tracker trays, the floating chat bar, board view
## cycling, the compact phase label, and safe-area handling.
##
## Moved verbatim from game_board.gd; the bridge below resolves the board
## widgets it restyles. Everything this module builds at runtime stays
## parented to the board root, so z-order and safe-area coordinates are
## unchanged. The eventual end state (phase 2) is a dedicated
## MobileGameBoard.tscn variant scene replacing this runtime restyling.

## The FAB grid opened/closed — GamepadBoardNav jails its cursor onto the
## expanded grid (the buttons never take real focus).
signal fab_toggled(expanded: bool)

var _board: Node

# --- Mobile state ---
var is_mobile_layout: bool = false
var _mobile_phase_label: Label = null
var _mobile_log_tray_open: bool = false
var _mobile_log_toggle_btn: Button = null
var _mobile_log_tween: Tween = null
# FAB (Floating Action Button) system for mobile action buttons
var _fab_main_btn: Button = null
var _fab_backdrop: ColorRect = null
var _fab_container: Control = null
var _fab_expanded: bool = false
var _fab_action_btns: Array[Button] = []
var _fab_labels: Array[Label] = []
var _fab_tween: Tween = null
var _mobile_log_badge: Label = null
var _mobile_log_unread: int = 0
enum MobileBoardView {LOCAL_ENLARGED, OPPONENT_ENLARGED, BALANCED}
var _mobile_board_view: int = MobileBoardView.LOCAL_ENLARGED
var _mobile_view_toggle_btn: Button = null
var _mobile_tracker_tray_open: bool = false
var _mobile_tracker_toggle_btn: Button = null
var _mobile_tracker_tween: Tween = null
var _mobile_cp_tray_open: bool = false
var _mobile_cp_toggle_btn: Button = null
var _mobile_cp_tween: Tween = null
var _mobile_cp_panel: PanelContainer = null
var _mobile_cp_panel_w: float = 180.0
var _mobile_cp_opp_cp_label: Label = null
var _mobile_cp_opp_threat_label: Label = null
var _mobile_cp_local_cp_label: Label = null
var _mobile_cp_local_threat_label: Label = null
var _mobile_menu_btn: Button = null
var _mobile_menu_panel: Control = null
var _mobile_menu_backdrop: ColorRect = null
var _mobile_menu_open: bool = false
var _mobile_sound_button: Button = null
var _mobile_music_button: Button = null
# Safe area insets in canvas units (set in _apply_safe_area_insets)
var _safe_left: float = 0.0
var _safe_right: float = 0.0
var _safe_top: float = 0.0
var _safe_bottom: float = 0.0
# Floating chat input bar that docks above the on-screen keyboard (mobile only)
var _mobile_chat_bar: PanelContainer = null
var _mobile_chat_input: LineEdit = null
var _mobile_chat_char_count: Label = null
var _mobile_chat_bar_lift: float = 0.0


func _ready() -> void:
	_board = get_parent()


# --- Board bridge: state/helpers still owned elsewhere ---
var _is_mobile_layout: bool:
	get: return is_mobile_layout
var turn_manager: TurnManager:
	get: return _board.turn_manager
var local_player_id: int:
	get: return _board.local_player_id
var is_multiplayer_game: bool:
	get: return _board.is_multiplayer_game
var _client_players: Array[PlayerState]:
	get: return _board._client_players
var _client_cp_modifiers: Array:
	get: return _board._client_cp_modifiers
var _client_threat_modifiers: Array:
	get: return _board._client_threat_modifiers

var action_panel: Control:
	get: return _board.action_panel
var btn_play_battle: Button:
	get: return _board.btn_play_battle
var btn_play_strategy: Button:
	get: return _board.btn_play_strategy
var btn_gain_rage: Button:
	get: return _board.btn_gain_rage
var btn_play_monster: Button:
	get: return _board.btn_play_monster
var btn_invade: Button:
	get: return _board.btn_invade
var btn_end_main: Button:
	get: return _board.btn_end_main
var btn_cancel: Button:
	get: return _board.btn_cancel
var btn_confirm: Button:
	get: return _board.btn_confirm
var btn_bug_report: Button:
	get: return _board.btn_bug_report
var btn_concede: Button:
	get: return _board.btn_concede
var btn_main_menu: Button:
	get: return _board.btn_main_menu
var btn_sound_toggle: Button:
	get: return _board.btn_sound_toggle
var btn_music_toggle: Button:
	get: return _board.btn_music_toggle
var btn_export_log: Button:
	get: return _board.btn_export_log
var btn_rematch: Button:
	get: return _board.btn_rematch
var btn_end_menu: Button:
	get: return _board.btn_end_menu
var chat_input: LineEdit:
	get: return _board.chat_input
var hand_toggle_button: Button:
	get: return _board.hand_toggle_button
var sort_hand_button: Button:
	get: return _board.sort_hand_button
var opponent_hand_toggle_button: Button:
	get: return _board.opponent_hand_toggle_button
var opponent_sort_hand_button: Button:
	get: return _board.opponent_sort_hand_button
var player1_board: Control:
	get: return _board.player1_board
var player2_board: Control:
	get: return _board.player2_board
var deck_search_skip: Button:
	get: return _board.deck_search_skip
var deck_search_show_all: CheckButton:
	get: return _board.deck_search_show_all
var deck_search_stacked: CheckButton:
	get: return _board.deck_search_stacked
var deck_search_view_board: Button:
	get: return _board.deck_search_view_board
var deck_arrange_confirm: Button:
	get: return _board.deck_arrange_confirm
var deck_arrange_view_board: Button:
	get: return _board.deck_arrange_view_board
var card_pool_select_skip: Button:
	get: return _board.card_pool_select_skip
var card_pool_select_confirm: Button:
	get: return _board.card_pool_select_confirm
var card_pool_select_show_all: CheckButton:
	get: return _board.card_pool_select_show_all
var card_pool_select_stacked: CheckButton:
	get: return _board.card_pool_select_stacked
var card_pool_select_view_board: Button:
	get: return _board.card_pool_select_view_board
var discard_view_close: Button:
	get: return _board.discard_view_close
var discard_view_stacked: CheckButton:
	get: return _board.discard_view_stacked
var monster_deck_view_close: Button:
	get: return _board.monster_deck_view_close
var monster_deck_view_stacked: CheckButton:
	get: return _board.monster_deck_view_stacked
var zone_stack_view_close: Button:
	get: return _board.zone_stack_view_close

var _preview_container: Control:
	get: return _board._preview_container
var _VOLUME_VALUE_KEYS: Array:
	get: return _board._VOLUME_VALUE_KEYS

func _on_bug_report_pressed() -> void:
	_board._on_bug_report_pressed()

func _on_concede_pressed() -> void:
	_board._on_concede_pressed()

func _on_export_log_pressed() -> void:
	_board._on_export_log_pressed()

func _dispatch_chat(text: String) -> void:
	_board._dispatch_chat(text)

func _fmt_num(n: int) -> String:
	return _board._fmt_num(n)

func _on_sound_toggle_pressed() -> void:
	_board._on_sound_toggle_pressed()

func _on_music_toggle_pressed() -> void:
	_board._on_music_toggle_pressed()

func _position_hands() -> void:
	_board._position_hands()

func _fit_button_text(btn: Button, base_size: int = 18, min_size: int = 10) -> void:
	_board._fit_button_text(btn, base_size, min_size)

func _on_main_menu_pressed() -> void:
	_board._on_main_menu_pressed()

func _resolve_translated_text(text: String) -> String:
	return _board._resolve_translated_text(text)

func _threat_mod_for(pid: int) -> int:
	return _board._threat_mod_for(pid)

func _get_player_state(pid: int) -> PlayerState:
	return _board._get_player_state(pid)


# --- Moved bodies (verbatim from game_board.gd) ---

func _apply_mobile_layout() -> void:
	# --- 1. Safe area insets (iOS notch/dynamic island, Android cutouts) ---
	# Must be computed FIRST so all button positioning can use _safe_left/_safe_right/etc.
	_apply_safe_area_insets()

	# --- 2. Expand board to use full width ---
	var left_spacer := _board.get_node("VBoxContainer/BoardArea/LeftSpacer")
	left_spacer.visible = false
	var right_spacer := _board.get_node("VBoxContainer/BoardArea/RightSpacer")
	right_spacer.visible = false
	var board_column := _board.get_node("VBoxContainer/BoardArea/BoardColumn")
	board_column.size_flags_stretch_ratio = 1.0

	# --- 3. Reserve bottom space for action panel, eliminate top spacer ---
	_board.get_node("VBoxContainer/TopSpacer").custom_minimum_size.y = 0
	_board.get_node("VBoxContainer/BottomSpacer").custom_minimum_size.y = 100

	# --- 3b. Constrain divider width to board content ---
	var divider := board_column.get_node("Divider") as ColorRect
	divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_update_mobile_divider.call_deferred()
	player1_board.resized.connect(_update_mobile_divider.call_deferred)
	player2_board.resized.connect(_update_mobile_divider.call_deferred)

	# --- 4. Board view sizing + toggle button ---
	_apply_mobile_board_view()
	_setup_mobile_view_toggle()

	# --- 5. Log panel as slide-out tray on the left ---
	_setup_mobile_log_tray()

	# --- 5a. Floating chat input bar that docks above the on-screen keyboard ---
	_setup_mobile_chat_bar()

	# --- 5b. CP/Threat tray above log button ---
	_setup_mobile_cp_tray()

	# --- 6. Hide card hover preview (mobile uses tap-to-zoom) ---
	if _preview_container:
		_preview_container.visible = false

	# --- 7. Touch-friendly action panel (full width at bottom) ---
	_apply_mobile_action_panel()

	# --- 8. Compact utility buttons into menu popup ---
	_apply_mobile_utility_buttons()

	# --- 9. Reposition hand button stacks ---
	_apply_mobile_hand_button_stacks()

	# --- 10. Widen overlay panels ---
	_apply_mobile_overlays()

	# --- 11. Phase indicator in top-right + turn tracker tray on right ---
	_create_mobile_phase_label()
	_setup_mobile_tracker_tray()

	# --- 12. Reposition action prompt ---
	_apply_mobile_action_prompt()

	# --- 13. Re-position hands for wider board ---
	_position_hands()

	# --- 14. Retry safe area after a brief delay ---
	# DisplayServer may not report safe area until the display is fully initialized.
	# If we got zeros, retry shortly so floating buttons get repositioned.
	if _safe_left == 0.0 and _safe_right == 0.0 and _safe_top == 0.0:
		get_tree().create_timer(0.2).timeout.connect(_retry_safe_area_insets, CONNECT_ONE_SHOT)


func _apply_mobile_action_panel() -> void:
	# Hide the default VBoxContainer panel — FAB replaces it
	action_panel.visible = false

	var pad_r := maxf(20.0, _safe_right + 4.0)
	var pad_b := maxf(20.0, _safe_bottom + 4.0)

	# --- Backdrop: full-screen dim overlay when FAB is expanded ---
	_fab_backdrop = ColorRect.new()
	_fab_backdrop.color = Color(0, 0, 0, 0.4)
	_fab_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fab_backdrop.z_index = 56
	_fab_backdrop.visible = false
	_fab_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fab_backdrop)
	_fab_backdrop.gui_input.connect(_on_fab_backdrop_input)

	# --- FAB container: holds the 5 action buttons + labels ---
	var btn_size := 85.0
	var col_gap := 12.0
	var row_gap := 8.0
	var label_h := 18.0
	var cell_h := btn_size + label_h + 2.0 # 105
	var grid_cols := 3
	var grid_w := btn_size * grid_cols + col_gap * (grid_cols - 1) # 279
	var container_w := grid_w + 20.0 # 299
	var container_h := cell_h * 2.0 + row_gap + btn_size + 8.0 # 311

	_fab_container = Control.new()
	_fab_container.anchor_left = 1.0
	_fab_container.anchor_right = 1.0
	_fab_container.anchor_top = 1.0
	_fab_container.anchor_bottom = 1.0
	_fab_container.offset_left = - (pad_r + container_w)
	_fab_container.offset_right = - pad_r
	_fab_container.offset_top = - (pad_b + container_h)
	_fab_container.offset_bottom = - pad_b
	_fab_container.z_index = 57
	_fab_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fab_container)

	# --- Main FAB button (always visible, bottom-right of container) ---
	_fab_main_btn = Button.new()
	_fab_main_btn.custom_minimum_size = Vector2(btn_size, btn_size)
	_fab_main_btn.size = Vector2(btn_size, btn_size)
	_fab_main_btn.position = Vector2(container_w - btn_size, container_h - btn_size)
	_fab_main_btn.pivot_offset = Vector2(btn_size / 2.0, btn_size / 2.0)
	_fab_main_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_fab_main_btn.clip_contents = true
	_fab_main_btn.pressed.connect(_toggle_fab)
	_fab_main_btn.draw.connect(_draw_fab_main_icon)
	_apply_circle_style(_fab_main_btn, Color(0.2, 0.45, 0.8))
	_fab_container.add_child(_fab_main_btn)

	# --- btn_end_main: standalone pill button, always visible alongside FAB ---
	btn_end_main.get_parent().remove_child(btn_end_main)
	btn_end_main.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_fab_container.add_child(btn_end_main)
	# --- btn_confirm / btn_cancel: standalone pill buttons, hidden by default ---
	btn_confirm.get_parent().remove_child(btn_confirm)
	btn_confirm.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn_confirm.disabled = true
	_fab_container.add_child(btn_confirm)
	btn_cancel.get_parent().remove_child(btn_cancel)
	btn_cancel.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn_cancel.disabled = true
	_fab_container.add_child(btn_cancel)
	_setup_standalone_buttons()

	# --- Reparent 5 action buttons into the FAB grid ---
	# Row 0: Battle, Monster, Strategy (3 cols)
	# Row 1: Rage, Invade (2 cols, centered)
	var btn_order: Array[Button] = [
		btn_play_battle, btn_play_monster, btn_play_strategy,
		btn_gain_rage, btn_invade
	]
	var btn_labels_text: Array = [
		tr("STR_TYPE_BATTLE"), tr("STR_TYPE_MONSTER"), tr("STR_TYPE_STRATEGY"),
		tr("STR_TYPE_RAGE"), tr("STR_GB_INVADE")
	]
	var btn_textures: Array[Texture2D] = [
		load("res://assets/ui/buttons/battle.png"),
		load("res://assets/ui/buttons/monster.png"),
		load("res://assets/ui/buttons/strategy.png"),
		load("res://assets/ui/buttons/rage.png"),
		load("res://assets/ui/buttons/invasion.png"),
	]

	var grid_left := (container_w - grid_w) / 2.0
	var fab_center := _fab_main_btn.position + Vector2(btn_size / 2.0, btn_size / 2.0)

	_fab_action_btns.clear()
	_fab_labels.clear()

	for i in range(5):
		var btn: Button = btn_order[i]
		var target_x: float
		var target_y: float
		if i < 3:
			# Row 0: 3 buttons evenly spaced
			target_x = grid_left + i * (btn_size + col_gap)
			target_y = 0.0
		else:
			# Row 1: 2 buttons centered under row 0
			var row1_offset := (grid_w - (btn_size * 2 + col_gap)) / 2.0
			target_x = grid_left + row1_offset + (i - 3) * (btn_size + col_gap)
			target_y = cell_h + row_gap

		btn.get_parent().remove_child(btn)
		btn.custom_minimum_size = Vector2(btn_size, btn_size)
		btn.size = Vector2(btn_size, btn_size)
		btn.text = ""
		btn.clip_contents = true
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.pivot_offset = Vector2(btn_size / 2.0, btn_size / 2.0)
		btn.position = fab_center - Vector2(btn_size / 2.0, btn_size / 2.0)
		btn.scale = Vector2.ZERO
		btn.visible = false
		btn.set_meta("fab_target_pos", Vector2(target_x, target_y))
		_apply_circle_style(btn, Color(0.2, 0.3, 0.5, 0.9))
		btn.draw.connect(_draw_btn_texture.bind(btn, btn_textures[i]))
		btn.pressed.connect(_collapse_fab_instant)
		_fab_container.add_child(btn)
		_fab_action_btns.append(btn)

		# Label below button
		var lbl := Label.new()
		lbl.text = btn_labels_text[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.custom_minimum_size = Vector2(btn_size + 8.0, label_h)
		lbl.size = Vector2(btn_size + 8.0, label_h)
		lbl.position = Vector2(target_x - 4.0, target_y + btn_size + 2.0)
		lbl.visible = false
		_fab_container.add_child(lbl)
		_fab_labels.append(lbl)


func _create_circle_stylebox(bg_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.corner_radius_top_left = 28
	sb.corner_radius_top_right = 28
	sb.corner_radius_bottom_left = 28
	sb.corner_radius_bottom_right = 28
	return sb


func _apply_circle_style(btn: Button, base_color: Color = Color(0.2, 0.3, 0.5, 0.9)) -> void:
	btn.add_theme_stylebox_override("normal", _create_circle_stylebox(base_color))
	btn.add_theme_stylebox_override("hover", _create_circle_stylebox(base_color.lightened(0.1)))
	btn.add_theme_stylebox_override("pressed", _create_circle_stylebox(base_color.darkened(0.15)))
	btn.add_theme_stylebox_override("disabled", _create_circle_stylebox(Color(0.3, 0.3, 0.3, 0.5)))


func _setup_standalone_buttons() -> void:
	## Position btn_end_main, btn_confirm, btn_cancel as pill-shaped text buttons above the FAB.
	var pill_w := 138.0
	var pill_h := 55.0
	var gap := 10.0
	var fab_cx := _fab_main_btn.position.x + _fab_main_btn.size.x / 2.0
	var fab_top := _fab_main_btn.position.y

	# btn_end_main: directly above FAB main button
	var end_main_y := fab_top - pill_h - gap
	_apply_pill_style(btn_end_main, pill_w, pill_h, fab_cx, end_main_y)

	# btn_confirm: above btn_end_main
	var confirm_y := end_main_y - pill_h - gap
	_apply_pill_style(btn_confirm, pill_w, pill_h, fab_cx, confirm_y)

	# btn_cancel: above btn_confirm
	var cancel_y := confirm_y - pill_h - gap
	_apply_pill_style(btn_cancel, pill_w, pill_h, fab_cx, cancel_y)


func _apply_pill_style(btn: Button, pill_w: float, pill_h: float, cx: float, y: float) -> void:
	btn.custom_minimum_size = Vector2(pill_w, pill_h)
	btn.size = Vector2(pill_w, pill_h)
	btn.position = Vector2(cx - pill_w / 2.0, y)
	btn.scale = Vector2.ONE
	btn.pivot_offset = Vector2.ZERO
	btn.add_theme_font_size_override("font_size", 18)
	var pill_sb := StyleBoxFlat.new()
	pill_sb.bg_color = Color(0.2, 0.3, 0.5, 0.9)
	pill_sb.corner_radius_top_left = 15
	pill_sb.corner_radius_top_right = 15
	pill_sb.corner_radius_bottom_left = 15
	pill_sb.corner_radius_bottom_right = 15
	btn.add_theme_stylebox_override("normal", pill_sb)
	var pill_hover := pill_sb.duplicate()
	pill_hover.bg_color = Color(0.25, 0.35, 0.55, 0.9)
	btn.add_theme_stylebox_override("hover", pill_hover)
	var pill_pressed := pill_sb.duplicate()
	pill_pressed.bg_color = Color(0.15, 0.25, 0.45, 0.9)
	btn.add_theme_stylebox_override("pressed", pill_pressed)
	var pill_disabled := pill_sb.duplicate()
	pill_disabled.bg_color = Color(0.3, 0.3, 0.3, 0.5)
	btn.add_theme_stylebox_override("disabled", pill_disabled)


func _apply_split_pill_style(left_btn: Button, right_btn: Button, height: float, radius: float) -> void:
	var bg_color := Color(0.2, 0.3, 0.5, 0.9)
	var hover_color := Color(0.25, 0.35, 0.55, 0.9)
	var pressed_color := Color(0.15, 0.25, 0.45, 0.9)

	for btn: Button in [left_btn, right_btn]:
		var is_left: bool = btn == left_btn
		btn.custom_minimum_size.y = height
		for state_name in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			match state_name:
				"normal": sb.bg_color = bg_color
				"hover": sb.bg_color = hover_color
				"pressed": sb.bg_color = pressed_color
			sb.corner_radius_top_left = int(radius) if is_left else 0
			sb.corner_radius_bottom_left = int(radius) if is_left else 0
			sb.corner_radius_top_right = 0 if is_left else int(radius)
			sb.corner_radius_bottom_right = 0 if is_left else int(radius)
			btn.add_theme_stylebox_override(state_name, sb)


func _apply_tab_style(btn: Button, edge_side: String) -> void:
	var bg_color := Color(0.2, 0.3, 0.5, 0.85)
	var hover_color := Color(0.25, 0.35, 0.55, 0.85)
	var pressed_color := Color(0.15, 0.25, 0.45, 0.85)
	var radius := 14
	var flush_on_left: bool = edge_side == "left"

	for state_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		match state_name:
			"normal": sb.bg_color = bg_color
			"hover": sb.bg_color = hover_color
			"pressed": sb.bg_color = pressed_color
		# Rounded on the side facing inward (where content expands from)
		sb.corner_radius_top_left = 0 if flush_on_left else radius
		sb.corner_radius_bottom_left = 0 if flush_on_left else radius
		sb.corner_radius_top_right = radius if flush_on_left else 0
		sb.corner_radius_bottom_right = radius if flush_on_left else 0
		btn.add_theme_stylebox_override(state_name, sb)
	var sb_disabled := StyleBoxFlat.new()
	sb_disabled.bg_color = Color(0.3, 0.3, 0.3, 0.5)
	sb_disabled.corner_radius_top_left = 0 if flush_on_left else radius
	sb_disabled.corner_radius_bottom_left = 0 if flush_on_left else radius
	sb_disabled.corner_radius_top_right = radius if flush_on_left else 0
	sb_disabled.corner_radius_bottom_right = radius if flush_on_left else 0
	btn.add_theme_stylebox_override("disabled", sb_disabled)


func _apply_mobile_utility_buttons() -> void:
	# Hide individual utility buttons — replaced by a single menu popup
	btn_bug_report.visible = false
	btn_concede.visible = false
	btn_main_menu.visible = false
	btn_sound_toggle.visible = false
	btn_music_toggle.visible = false
	btn_export_log.visible = false

	# Create a styled menu button in the top-right corner
	_mobile_menu_btn = Button.new()
	_mobile_menu_btn.text = "..."
	_mobile_menu_btn.anchor_left = 1.0
	_mobile_menu_btn.anchor_right = 1.0
	_mobile_menu_btn.anchor_top = 0.0
	_mobile_menu_btn.anchor_bottom = 0.0
	var menu_pad_r := maxf(20.0, _safe_right + 4.0)
	var menu_pad_t := maxf(40.0, _safe_top + 24.0)
	_mobile_menu_btn.offset_left = - (menu_pad_r + 58.0)
	_mobile_menu_btn.offset_top = menu_pad_t
	_mobile_menu_btn.offset_right = - menu_pad_r
	_mobile_menu_btn.offset_bottom = menu_pad_t + 55.0
	_mobile_menu_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mobile_menu_btn.custom_minimum_size.y = 55
	_mobile_menu_btn.add_theme_font_size_override("font_size", 20)
	_mobile_menu_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_mobile_menu_btn.z_index = 50
	_apply_mobile_menu_pill_style(_mobile_menu_btn)
	_mobile_menu_btn.pressed.connect(_toggle_mobile_menu)
	add_child(_mobile_menu_btn)

	# Backdrop: dims screen when menu is open
	_mobile_menu_backdrop = ColorRect.new()
	_mobile_menu_backdrop.color = Color(0, 0, 0, 0.4)
	_mobile_menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mobile_menu_backdrop.z_index = 55
	_mobile_menu_backdrop.visible = false
	_mobile_menu_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_mobile_menu_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_mobile_menu()
	)
	add_child(_mobile_menu_backdrop)

	# Panel with large option buttons
	_mobile_menu_panel = VBoxContainer.new()
	_mobile_menu_panel.anchor_left = 1.0
	_mobile_menu_panel.anchor_right = 1.0
	_mobile_menu_panel.anchor_top = 0.0
	_mobile_menu_panel.anchor_bottom = 0.0
	var panel_w := 200.0
	var btn_h := 55.0
	var gap := 6.0
	var panel_top := menu_pad_t + 55.0 + 8.0
	_mobile_menu_panel.offset_left = - (menu_pad_r + panel_w)
	_mobile_menu_panel.offset_right = - menu_pad_r
	_mobile_menu_panel.offset_top = panel_top
	_mobile_menu_panel.offset_bottom = panel_top + (btn_h + gap) * 4.0
	_mobile_menu_panel.add_theme_constant_override("separation", int(gap))
	_mobile_menu_panel.z_index = 56
	_mobile_menu_panel.visible = false
	_mobile_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mobile_menu_panel)

	for item in [[tr("STR_GB_REPORT_BUG"), _on_bug_report_pressed], [tr("STR_GB_CONCEDE"), _on_concede_pressed], [tr("STR_GB_MAIN_MENU"), _on_main_menu_pressed], [tr("STR_GB_EXPORT_LOG"), _on_export_log_pressed]]:
		var btn := Button.new()
		btn.text = item[0]
		btn.custom_minimum_size.y = btn_h
		btn.add_theme_font_size_override("font_size", 18)
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		_apply_mobile_menu_pill_style(btn)
		btn.pressed.connect(func():
			_close_mobile_menu()
			(item[1] as Callable).call()
		)
		_mobile_menu_panel.add_child(btn)

	# Sound toggle in mobile menu
	var sound_btn := Button.new()
	sound_btn.text = tr("STR_GB_SOUND_FMT").replace("{VAL}", tr(_VOLUME_VALUE_KEYS[GameSettings.sound_volume]))
	sound_btn.custom_minimum_size.y = btn_h
	sound_btn.add_theme_font_size_override("font_size", 18)
	sound_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_mobile_menu_pill_style(sound_btn)
	sound_btn.pressed.connect(func():
		_on_sound_toggle_pressed()
	)
	_mobile_menu_panel.add_child(sound_btn)
	_mobile_sound_button = sound_btn

	# Music toggle in mobile menu
	var music_btn := Button.new()
	music_btn.text = tr("STR_GB_MUSIC_FMT").replace("{VAL}", tr(_VOLUME_VALUE_KEYS[GameSettings.music_volume]))
	music_btn.custom_minimum_size.y = btn_h
	music_btn.add_theme_font_size_override("font_size", 18)
	music_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_mobile_menu_pill_style(music_btn)
	music_btn.pressed.connect(func():
		_on_music_toggle_pressed()
	)
	_mobile_menu_panel.add_child(music_btn)
	_mobile_music_button = music_btn

	# Expand panel height for the extra buttons
	_mobile_menu_panel.offset_bottom += (btn_h + gap) * 2

	# Controller: the open panel is a modal focus context (the board cursor
	# parks while it is up and returns to sys_menu on close) with a fully
	# pinned vertical wrap mesh — left/right self-loop so the geometric
	# auto-neighbor can't escape onto board chrome.
	GamepadHelper.register_modal(_mobile_menu_panel)
	var menu_opts: Array[Button] = []
	for child in _mobile_menu_panel.get_children():
		if child is Button:
			menu_opts.append(child)
	for i in menu_opts.size():
		var opt := menu_opts[i]
		GamepadHelper.make_pad_focusable(opt)
		var prev := menu_opts[(i - 1 + menu_opts.size()) % menu_opts.size()]
		var next := menu_opts[(i + 1) % menu_opts.size()]
		opt.focus_neighbor_top = opt.get_path_to(prev)
		opt.focus_neighbor_bottom = opt.get_path_to(next)
		opt.focus_previous = opt.get_path_to(prev)
		opt.focus_next = opt.get_path_to(next)
		opt.focus_neighbor_left = opt.get_path_to(opt)
		opt.focus_neighbor_right = opt.get_path_to(opt)

	# Hand toggle/sort buttons — fire on touch-down
	for btn: Button in [hand_toggle_button, sort_hand_button,
			opponent_hand_toggle_button, opponent_sort_hand_button]:
		btn.custom_minimum_size.y = 60
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

	# Minimize chip — fire on touch-down (sizing/clearance handled in show_chip)
	_board._minimize_chip.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

	# End game buttons
	btn_rematch.custom_minimum_size.y = 60
	btn_rematch.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn_end_menu.custom_minimum_size.y = 60
	btn_end_menu.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS


func _apply_mobile_menu_pill_style(btn: Button) -> void:
	var bg_color := Color(0.2, 0.3, 0.5, 0.9)
	var hover_color := Color(0.25, 0.35, 0.55, 0.9)
	var pressed_color := Color(0.15, 0.25, 0.45, 0.9)
	for state_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		match state_name:
			"normal": sb.bg_color = bg_color
			"hover": sb.bg_color = hover_color
			"pressed": sb.bg_color = pressed_color
		sb.corner_radius_top_left = 15
		sb.corner_radius_top_right = 15
		sb.corner_radius_bottom_left = 15
		sb.corner_radius_bottom_right = 15
		btn.add_theme_stylebox_override(state_name, sb)


func _toggle_mobile_menu() -> void:
	if _mobile_menu_open:
		_close_mobile_menu()
	else:
		_open_mobile_menu()


## B/ESC closes the "..." menu. Acts on the LEADING face of the cancel press
## (raw button / pad_cancel / ui_cancel — whichever lands first) and swallows
## the twins so the board's ui_cancel ladder can't also fire; the swallow
## check runs before the open gate so a twin arriving after the close still
## dies here instead of leaking to the ladder.
func _input(event: InputEvent) -> void:
	if not is_mobile_layout:
		return
	# Unconditional: the twin of the press that closed the menu arrives after
	# _mobile_menu_open is already false (scene _input runs BEFORE the
	# GamepadHelper autoload's root-stage kill, so it must die here).
	if GamepadHelper.is_swallowed_cancel(event):
		get_viewport().set_input_as_handled()
		return
	if not _mobile_menu_open:
		return
	if not GamepadHelper.is_cancel_press(event):
		return
	GamepadHelper.swallow_cancel_twins()
	_close_mobile_menu()
	get_viewport().set_input_as_handled()


func _open_mobile_menu() -> void:
	_mobile_menu_open = true
	_mobile_menu_backdrop.visible = true
	_mobile_menu_panel.visible = true


func _close_mobile_menu() -> void:
	_mobile_menu_open = false
	_mobile_menu_backdrop.visible = false
	_mobile_menu_panel.visible = false


func _update_mobile_divider() -> void:
	var divider := _board.get_node("VBoxContainer/BoardArea/BoardColumn/Divider") as ColorRect
	# Use the wider of the two boards' LayoutContainer widths
	var lc1 := player1_board.get_node("LayoutContainer") as Control
	var lc2 := player2_board.get_node("LayoutContainer") as Control
	var w := maxf(lc1.size.x, lc2.size.x)
	if w > 0.0:
		divider.custom_minimum_size.x = w


func _apply_mobile_board_view() -> void:
	var local_board: Control = player1_board if local_player_id == 0 else player2_board
	var opponent_board: Control = player2_board if local_player_id == 0 else player1_board
	match _mobile_board_view:
		MobileBoardView.LOCAL_ENLARGED:
			local_board.size_flags_stretch_ratio = 0.62
			opponent_board.size_flags_stretch_ratio = 0.38
			local_board.apply_mobile_label_scale(1.0)
			opponent_board.apply_mobile_label_scale(0.6)
		MobileBoardView.OPPONENT_ENLARGED:
			local_board.size_flags_stretch_ratio = 0.38
			opponent_board.size_flags_stretch_ratio = 0.62
			local_board.apply_mobile_label_scale(0.6)
			opponent_board.apply_mobile_label_scale(1.0)
		MobileBoardView.BALANCED:
			local_board.size_flags_stretch_ratio = 0.5
			opponent_board.size_flags_stretch_ratio = 0.5
			local_board.apply_mobile_label_scale(1.0)
			opponent_board.apply_mobile_label_scale(1.0)


func _setup_mobile_view_toggle() -> void:
	_mobile_view_toggle_btn = Button.new()
	_mobile_view_toggle_btn.custom_minimum_size = Vector2(55, 60)
	# Anchored to bottom-left — positioned dynamically in _position_hands()
	_mobile_view_toggle_btn.anchor_left = 0.0
	_mobile_view_toggle_btn.anchor_right = 0.0
	_mobile_view_toggle_btn.anchor_top = 1.0
	_mobile_view_toggle_btn.anchor_bottom = 1.0
	_mobile_view_toggle_btn.z_index = 61
	_mobile_view_toggle_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_mobile_view_toggle_btn.pressed.connect(_cycle_mobile_board_view)
	add_child(_mobile_view_toggle_btn)
	# Apply pill style matching the hand buttons
	var bg_color := Color(0.2, 0.3, 0.5, 0.9)
	var hover_color := Color(0.25, 0.35, 0.55, 0.9)
	var pressed_color := Color(0.15, 0.25, 0.45, 0.9)
	for state_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		match state_name:
			"normal": sb.bg_color = bg_color
			"hover": sb.bg_color = hover_color
			"pressed": sb.bg_color = pressed_color
		sb.corner_radius_top_left = 15
		sb.corner_radius_top_right = 15
		sb.corner_radius_bottom_left = 15
		sb.corner_radius_bottom_right = 15
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		_mobile_view_toggle_btn.add_theme_stylebox_override(state_name, sb)
	# Draw the icon via a custom draw callback
	_mobile_view_toggle_btn.draw.connect(_draw_board_view_icon)
	_mobile_view_toggle_btn.queue_redraw()


func _cycle_mobile_board_view() -> void:
	_mobile_board_view = (_mobile_board_view + 1) % 3
	_apply_mobile_board_view()
	_mobile_view_toggle_btn.queue_redraw()


func _draw_board_view_icon() -> void:
	var btn := _mobile_view_toggle_btn
	if not btn:
		return
	var w := btn.size.x
	var h := btn.size.y
	var pad := 12.0
	var gap := 3.0
	var box_w := w - pad * 2.0
	var total_h := h - pad * 2.0
	var top_ratio: float
	var bot_ratio: float
	match _mobile_board_view:
		MobileBoardView.LOCAL_ENLARGED:
			top_ratio = 0.35 # opponent = small
			bot_ratio = 0.65 # you = large
		MobileBoardView.OPPONENT_ENLARGED:
			top_ratio = 0.65 # opponent = large
			bot_ratio = 0.35 # you = small
		_:
			top_ratio = 0.5
			bot_ratio = 0.5
	var top_h := (total_h - gap) * top_ratio
	var bot_h := (total_h - gap) * bot_ratio
	var x := pad
	var color := Color(0.85, 0.85, 0.85)
	# Top box (opponent)
	btn.draw_rect(Rect2(x, pad, box_w, top_h), color, false, 1.5)
	# Bottom box (you)
	btn.draw_rect(Rect2(x, pad + top_h + gap, box_w, bot_h), color, false, 1.5)


func _setup_mobile_log_tray() -> void:
	var log_panel := _board.get_node("LogPanel") as PanelContainer
	var log_bg := StyleBoxFlat.new()
	log_bg.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	log_bg.corner_radius_top_right = 10
	log_bg.corner_radius_bottom_right = 10
	log_panel.add_theme_stylebox_override("panel", log_bg)
	# Position log panel as a left-side tray that slides in/out
	log_panel.anchor_left = 0.0
	log_panel.anchor_right = 0.0
	log_panel.anchor_top = 0.1
	log_panel.anchor_bottom = 0.85
	log_panel.offset_left = 0.0
	log_panel.offset_right = 320.0
	log_panel.offset_top = 0.0
	log_panel.offset_bottom = 0.0
	log_panel.z_index = 90
	# Start hidden off-screen to the left
	log_panel.position.x = -320.0
	log_panel.visible = true

	# Toggle button pinned to the left edge
	_mobile_log_toggle_btn = Button.new()
	_mobile_log_toggle_btn.text = tr("STR_GB_LOG")
	_mobile_log_toggle_btn.custom_minimum_size = Vector2(50, 75)
	_mobile_log_toggle_btn.anchor_left = 0.0
	_mobile_log_toggle_btn.anchor_right = 0.0
	_mobile_log_toggle_btn.anchor_top = 0.5
	_mobile_log_toggle_btn.anchor_bottom = 0.5
	var log_pad_l := maxf(4.0, _safe_left)
	_mobile_log_toggle_btn.offset_left = log_pad_l
	_mobile_log_toggle_btn.offset_top = -38.0
	_mobile_log_toggle_btn.offset_right = log_pad_l + 50.0
	_mobile_log_toggle_btn.offset_bottom = 37.0
	_mobile_log_toggle_btn.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mobile_log_toggle_btn.add_theme_font_size_override("font_size", 15)
	_mobile_log_toggle_btn.z_index = 91
	_mobile_log_toggle_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_tab_style(_mobile_log_toggle_btn, "left")
	_mobile_log_toggle_btn.pressed.connect(_toggle_mobile_log_tray)
	add_child(_mobile_log_toggle_btn)

	# Unread chat badge (red circle with count, hidden by default)
	_mobile_log_badge = Label.new()
	_mobile_log_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mobile_log_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mobile_log_badge.custom_minimum_size = Vector2(25, 25)
	_mobile_log_badge.add_theme_font_size_override("font_size", 14)
	_mobile_log_badge.add_theme_color_override("font_color", Color.WHITE)
	var badge_bg := StyleBoxFlat.new()
	badge_bg.bg_color = Color(0.85, 0.15, 0.15)
	badge_bg.corner_radius_top_left = 12
	badge_bg.corner_radius_top_right = 12
	badge_bg.corner_radius_bottom_left = 12
	badge_bg.corner_radius_bottom_right = 12
	badge_bg.content_margin_left = 5
	badge_bg.content_margin_right = 5
	_mobile_log_badge.add_theme_stylebox_override("normal", badge_bg)
	_mobile_log_badge.anchor_left = 1.0
	_mobile_log_badge.anchor_top = 0.0
	_mobile_log_badge.offset_left = -8.0
	_mobile_log_badge.offset_top = -6.0
	_mobile_log_badge.offset_right = 12.0
	_mobile_log_badge.offset_bottom = 14.0
	_mobile_log_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_log_badge.visible = false
	_mobile_log_toggle_btn.add_child(_mobile_log_badge)


func _setup_mobile_chat_bar() -> void:
	# Only worth doing where the OS shows a virtual keyboard that would cover the
	# in-tray chat field. With a hardware keyboard (or the mobile layout forced on
	# desktop), leave the tray field editable and skip the floating bar entirely.
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return

	# An editable chat field at the bottom of the tray would sit behind the OS
	# keyboard, so on mobile the in-tray field becomes a tap target that opens a
	# floating input bar which docks just above the keyboard instead.
	chat_input.editable = false
	chat_input.gui_input.connect(_on_tray_chat_tapped)

	_mobile_chat_bar = PanelContainer.new()
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	bar_bg.content_margin_left = 10
	bar_bg.content_margin_right = 10
	bar_bg.content_margin_top = 8
	bar_bg.content_margin_bottom = 8
	_mobile_chat_bar.add_theme_stylebox_override("panel", bar_bg)
	# Full-width strip pinned to the bottom edge, growing upward.
	_mobile_chat_bar.anchor_left = 0.0
	_mobile_chat_bar.anchor_right = 1.0
	_mobile_chat_bar.anchor_top = 1.0
	_mobile_chat_bar.anchor_bottom = 1.0
	_mobile_chat_bar.offset_left = 0.0
	_mobile_chat_bar.offset_right = 0.0
	_mobile_chat_bar.offset_top = -64.0
	_mobile_chat_bar.offset_bottom = 0.0
	_mobile_chat_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_mobile_chat_bar.z_index = 200
	_mobile_chat_bar.visible = false
	add_child(_mobile_chat_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_mobile_chat_bar.add_child(row)

	_mobile_chat_input = LineEdit.new()
	_mobile_chat_input.placeholder_text = tr("STR_GB_CHAT_PLACEHOLDER")
	_mobile_chat_input.max_length = chat_input.max_length
	_mobile_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_chat_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mobile_chat_input.text_submitted.connect(_on_mobile_chat_submitted)
	_mobile_chat_input.text_changed.connect(_on_mobile_chat_text_changed)
	_mobile_chat_input.focus_exited.connect(_close_mobile_chat_bar)
	row.add_child(_mobile_chat_input)

	_mobile_chat_char_count = Label.new()
	_mobile_chat_char_count.text = str(_mobile_chat_input.max_length)
	_mobile_chat_char_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mobile_chat_char_count.add_theme_font_size_override("font_size", 13)
	_mobile_chat_char_count.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(_mobile_chat_char_count)


func _on_tray_chat_tapped(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	if tapped:
		_open_mobile_chat_bar()


func _open_mobile_chat_bar() -> void:
	if _mobile_chat_bar == null:
		return
	_mobile_chat_input.text = ""
	_mobile_chat_char_count.text = str(_mobile_chat_input.max_length)
	_mobile_chat_bar_lift = 0.0
	_mobile_chat_bar.position.y = 0.0
	_mobile_chat_bar.visible = true
	_mobile_chat_input.grab_focus()  # triggers the OS keyboard


func _close_mobile_chat_bar() -> void:
	if _mobile_chat_bar == null or not _mobile_chat_bar.visible:
		return
	_mobile_chat_bar.visible = false
	if _mobile_chat_input.has_focus():
		_mobile_chat_input.release_focus()


func _on_mobile_chat_submitted(text: String) -> void:
	_dispatch_chat(text)
	_mobile_chat_input.clear()
	_mobile_chat_char_count.text = str(_mobile_chat_input.max_length)
	# Keep focus so the player can send several messages without re-tapping.


func _on_mobile_chat_text_changed(new_text: String) -> void:
	_mobile_chat_char_count.text = str(_mobile_chat_input.max_length - new_text.length())


func _notify_mobile_log_chat() -> void:
	if not _is_mobile_layout or _mobile_log_tray_open:
		return
	_mobile_log_unread += 1
	if _mobile_log_badge:
		_mobile_log_badge.text = str(_mobile_log_unread)
		_mobile_log_badge.visible = true


func _clear_mobile_log_badge() -> void:
	_mobile_log_unread = 0
	if _mobile_log_badge:
		_mobile_log_badge.visible = false


func _toggle_mobile_log_tray() -> void:
	var log_panel := _board.get_node("LogPanel") as PanelContainer
	_mobile_log_tray_open = not _mobile_log_tray_open

	if _mobile_log_tween and _mobile_log_tween.is_valid():
		_mobile_log_tween.kill()
	_mobile_log_tween = create_tween()
	_mobile_log_tween.set_ease(Tween.EASE_OUT)
	_mobile_log_tween.set_trans(Tween.TRANS_CUBIC)

	var log_pad := maxf(4.0, _safe_left)
	if _mobile_log_tray_open:
		_clear_mobile_log_badge()
		_mobile_log_tween.tween_property(log_panel, "position:x", 0.0, 0.25)
		_mobile_log_tween.parallel().tween_property(_mobile_log_toggle_btn, "offset_left", 320.0 + log_pad, 0.25)
		_mobile_log_tween.parallel().tween_property(_mobile_log_toggle_btn, "offset_right", 370.0 + log_pad, 0.25)
	else:
		_mobile_log_tween.tween_property(log_panel, "position:x", -320.0, 0.25)
		_mobile_log_tween.parallel().tween_property(_mobile_log_toggle_btn, "offset_left", log_pad, 0.25)
		_mobile_log_tween.parallel().tween_property(_mobile_log_toggle_btn, "offset_right", log_pad + 50.0, 0.25)


func _setup_mobile_cp_tray() -> void:
	# Panel container for CP/Threat display
	_mobile_cp_panel = PanelContainer.new()
	var safe_pad := maxf(0.0, _safe_left)
	_mobile_cp_panel_w = 180.0 + safe_pad
	var cp_bg := StyleBoxFlat.new()
	cp_bg.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	cp_bg.corner_radius_top_right = 10
	cp_bg.corner_radius_bottom_right = 10
	cp_bg.content_margin_left = 12 + safe_pad
	cp_bg.content_margin_right = 12
	cp_bg.content_margin_top = 10
	cp_bg.content_margin_bottom = 10
	_mobile_cp_panel.add_theme_stylebox_override("panel", cp_bg)
	_mobile_cp_panel.anchor_left = 0.0
	_mobile_cp_panel.anchor_right = 0.0
	_mobile_cp_panel.anchor_top = 0.5
	_mobile_cp_panel.anchor_bottom = 0.5
	_mobile_cp_panel.offset_left = 0.0
	_mobile_cp_panel.offset_right = _mobile_cp_panel_w
	_mobile_cp_panel.offset_top = -135.0
	_mobile_cp_panel.offset_bottom = -25.0
	_mobile_cp_panel.z_index = 90
	_mobile_cp_panel.position.x = -_mobile_cp_panel_w
	add_child(_mobile_cp_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_mobile_cp_panel.add_child(vbox)

	# Opponent row (top: CP | Threat)
	var opp_row := HBoxContainer.new()
	_mobile_cp_opp_cp_label = Label.new()
	_mobile_cp_opp_cp_label.text = "0"
	_mobile_cp_opp_cp_label.add_theme_font_size_override("font_size", 14)
	_mobile_cp_opp_cp_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	_mobile_cp_opp_cp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_cp_opp_cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opp_row.add_child(_mobile_cp_opp_cp_label)
	_mobile_cp_opp_threat_label = Label.new()
	_mobile_cp_opp_threat_label.text = "0"
	_mobile_cp_opp_threat_label.add_theme_font_size_override("font_size", 14)
	_mobile_cp_opp_threat_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
	_mobile_cp_opp_threat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_cp_opp_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opp_row.add_child(_mobile_cp_opp_threat_label)
	vbox.add_child(opp_row)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	vbox.add_child(sep)

	# Local player row (bottom — Threat | CP, mirrored from opponent)
	var local_row := HBoxContainer.new()
	_mobile_cp_local_threat_label = Label.new()
	_mobile_cp_local_threat_label.text = "0"
	_mobile_cp_local_threat_label.add_theme_font_size_override("font_size", 14)
	_mobile_cp_local_threat_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
	_mobile_cp_local_threat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_cp_local_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	local_row.add_child(_mobile_cp_local_threat_label)
	_mobile_cp_local_cp_label = Label.new()
	_mobile_cp_local_cp_label.text = "0"
	_mobile_cp_local_cp_label.add_theme_font_size_override("font_size", 14)
	_mobile_cp_local_cp_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	_mobile_cp_local_cp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_cp_local_cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	local_row.add_child(_mobile_cp_local_cp_label)
	vbox.add_child(local_row)

	# Toggle button above Log button
	_mobile_cp_toggle_btn = Button.new()
	_mobile_cp_toggle_btn.text = tr("STR_GB_CP")
	_mobile_cp_toggle_btn.custom_minimum_size = Vector2(50, 75)
	_mobile_cp_toggle_btn.anchor_left = 0.0
	_mobile_cp_toggle_btn.anchor_right = 0.0
	_mobile_cp_toggle_btn.anchor_top = 0.5
	_mobile_cp_toggle_btn.anchor_bottom = 0.5
	var cp_pad_l := maxf(4.0, _safe_left)
	_mobile_cp_toggle_btn.offset_left = cp_pad_l
	_mobile_cp_toggle_btn.offset_top = -117.0
	_mobile_cp_toggle_btn.offset_right = cp_pad_l + 50.0
	_mobile_cp_toggle_btn.offset_bottom = -42.0
	_mobile_cp_toggle_btn.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mobile_cp_toggle_btn.add_theme_font_size_override("font_size", 15)
	_mobile_cp_toggle_btn.z_index = 91
	_mobile_cp_toggle_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_tab_style(_mobile_cp_toggle_btn, "left")
	_mobile_cp_toggle_btn.pressed.connect(_toggle_mobile_cp_tray)
	add_child(_mobile_cp_toggle_btn)


func _toggle_mobile_cp_tray() -> void:
	_mobile_cp_tray_open = not _mobile_cp_tray_open

	if _mobile_cp_tween and _mobile_cp_tween.is_valid():
		_mobile_cp_tween.kill()
	_mobile_cp_tween = create_tween()
	_mobile_cp_tween.set_ease(Tween.EASE_OUT)
	_mobile_cp_tween.set_trans(Tween.TRANS_CUBIC)

	var cp_pad := maxf(4.0, _safe_left)
	if _mobile_cp_tray_open:
		_mobile_cp_tween.tween_property(_mobile_cp_panel, "position:x", 0.0, 0.25)
		_mobile_cp_tween.parallel().tween_property(_mobile_cp_toggle_btn, "offset_left", _mobile_cp_panel_w + cp_pad, 0.25)
		_mobile_cp_tween.parallel().tween_property(_mobile_cp_toggle_btn, "offset_right", _mobile_cp_panel_w + 50.0 + cp_pad, 0.25)
	else:
		_mobile_cp_tween.tween_property(_mobile_cp_panel, "position:x", -_mobile_cp_panel_w, 0.25)
		_mobile_cp_tween.parallel().tween_property(_mobile_cp_toggle_btn, "offset_left", cp_pad, 0.25)
		_mobile_cp_tween.parallel().tween_property(_mobile_cp_toggle_btn, "offset_right", cp_pad + 50.0, 0.25)


func _sync_mobile_cp_tray() -> void:
	if not _mobile_cp_opp_cp_label:
		return
	var states: Array[PlayerState] = [null, null]
	var cp_mods: Array[int] = [0, 0]
	var threat_mods: Array[int] = [0, 0]
	if turn_manager and turn_manager.game_state:
		states[0] = turn_manager.game_state.players[0]
		states[1] = turn_manager.game_state.players[1]
		var eh := turn_manager.effect_handler
		if eh:
			for pid in 2:
				cp_mods[pid] += eh.get_monster_cp_modifier(pid)
				var zone_cp: Array = eh.get_zone_cp_modifiers(pid)
				var strat_cp: Array = eh.get_strategy_cp_modifiers(pid)
				for v in zone_cp: cp_mods[pid] += v
				for v in strat_cp: cp_mods[pid] += v
				threat_mods[pid] = eh.get_threat_level_modifier(pid)
	elif not _client_players.is_empty():
		states[0] = _client_players[0]
		states[1] = _client_players[1]
		cp_mods[0] = _client_cp_modifiers[0]
		cp_mods[1] = _client_cp_modifiers[1]
		threat_mods[0] = _client_threat_modifiers[0]
		threat_mods[1] = _client_threat_modifiers[1]
	var lid: int = local_player_id
	var oid: int = 1 - lid
	if states[lid]:
		_mobile_cp_local_cp_label.text = _fmt_num(states[lid].get_total_counter_power() + cp_mods[lid])
		_mobile_cp_local_threat_label.text = _fmt_num(states[lid].get_threat_level() + threat_mods[lid])
	if states[oid]:
		_mobile_cp_opp_cp_label.text = _fmt_num(states[oid].get_total_counter_power() + cp_mods[oid])
		_mobile_cp_opp_threat_label.text = _fmt_num(states[oid].get_threat_level() + threat_mods[oid])


func _apply_mobile_hand_button_stacks() -> void:
	# Stacks are dynamically positioned in _position_hands() on mobile,
	# placed to the left of the hand / opponent board. Set anchors to 0,0
	# for absolute offset positioning.
	var hand_stack := _board.get_node("HandButtonStack") as HBoxContainer
	hand_stack.anchor_left = 0.0
	hand_stack.anchor_right = 0.0
	hand_stack.anchor_top = 0.0
	hand_stack.anchor_bottom = 0.0
	hand_stack.grow_horizontal = Control.GROW_DIRECTION_END
	hand_stack.z_index = 56
	hand_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var opp_stack := _board.get_node("OpponentHandButtonStack") as HBoxContainer
	opp_stack.anchor_left = 0.0
	opp_stack.anchor_right = 0.0
	opp_stack.anchor_top = 0.0
	opp_stack.anchor_bottom = 0.0
	opp_stack.grow_horizontal = Control.GROW_DIRECTION_END
	opp_stack.z_index = 56
	opp_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Apply split-pill styling: [▲|Sort] / [▼|Sort]
	_apply_split_pill_style(hand_toggle_button, sort_hand_button, 60.0, 15.0)
	_apply_split_pill_style(opponent_hand_toggle_button, opponent_sort_hand_button, 60.0, 15.0)


func _apply_mobile_action_prompt() -> void:
	# Position action prompt in bottom-left, capped at 25% screen width.
	# Grows vertically upward if text wraps.
	var prompt := _board.get_node("ActionPrompt") as PanelContainer
	var pad_l := maxf(20.0, _safe_left + 4.0)
	prompt.anchor_left = 0.0
	prompt.anchor_right = 0.25
	prompt.anchor_top = 1.0
	prompt.anchor_bottom = 1.0
	prompt.offset_left = pad_l
	prompt.offset_top = -186.0
	prompt.offset_right = 0.0
	prompt.offset_bottom = -160.0
	prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt.z_index = 56


func _apply_mobile_overlays() -> void:
	# Increase scroll deadzone so touch scrolling doesn't accidentally tap cards
	for scroll_path in [
		"DeckSearchOverlay/DeckSearchPanel/VBox/ScrollContainer",
		"DiscardViewOverlay/DiscardViewPanel/VBox/ScrollContainer",
		"MonsterDeckViewOverlay/MonsterDeckViewPanel/VBox/ScrollContainer",
		"ZoneStackViewOverlay/ZoneStackViewPanel/VBox/ScrollContainer",
		"CardSelectOverlay/CardSelectPanel/VBox/ContentContainer/PoolPanel/PoolVBox/ScrollContainer",
		"CardSelectOverlay/CardSelectPanel/VBox/ContentContainer/SelectionPanel/SelectionVBox/ScrollContainer",
	]:
		var sc: ScrollContainer = get_node_or_null(scroll_path)
		if sc:
			sc.scroll_deadzone = 40

	# Touch-friendly close/skip/confirm buttons
	for btn: Button in [deck_search_skip, discard_view_close, monster_deck_view_close,
			zone_stack_view_close, deck_arrange_confirm, deck_arrange_view_board,
			deck_search_view_board, card_pool_select_skip, card_pool_select_confirm,
			card_pool_select_view_board]:
		btn.custom_minimum_size.y = 55
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

	# Touch-friendly CheckButton toggles
	for cb: CheckButton in [deck_search_show_all, deck_search_stacked,
			discard_view_stacked, monster_deck_view_stacked,
			card_pool_select_show_all, card_pool_select_stacked]:
		cb.custom_minimum_size.y = 55
		cb.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS


func _create_mobile_phase_label() -> void:
	_mobile_phase_label = Label.new()
	_mobile_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mobile_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mobile_phase_label.add_theme_font_size_override("font_size", 13)
	_mobile_phase_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	# Top-right corner
	_mobile_phase_label.anchor_left = 0.5
	_mobile_phase_label.anchor_right = 1.0
	_mobile_phase_label.anchor_top = 0.0
	_mobile_phase_label.anchor_bottom = 0.0
	var phase_pad_r := maxf(60.0, _safe_right + 50.0) # Leave room for "..." menu button
	var phase_pad_t := maxf(20.0, _safe_top + 4.0)
	_mobile_phase_label.offset_left = 0.0
	_mobile_phase_label.offset_top = phase_pad_t
	_mobile_phase_label.offset_right = - phase_pad_r
	_mobile_phase_label.offset_bottom = phase_pad_t + 18.0
	_mobile_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_phase_label.z_index = 50
	add_child(_mobile_phase_label)


func _setup_mobile_tracker_tray() -> void:
	# Move the TurnTracker out of the hidden RightSpacer into a right-side tray
	var tracker := _board.get_node("VBoxContainer/BoardArea/RightSpacer/TurnTracker") as VBoxContainer
	var turn_label_margin := _board.get_node("VBoxContainer/BoardArea/RightSpacer/TurnLabelMargin")

	# Create a panel to hold the tracker
	var panel := PanelContainer.new()
	panel.name = "MobileTrackerPanel"
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	panel_bg.corner_radius_top_left = 10
	panel_bg.corner_radius_bottom_left = 10
	panel.add_theme_stylebox_override("panel", panel_bg)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.05
	panel.anchor_bottom = 0.85
	panel.offset_left = -140.0
	panel.offset_right = 0.0
	panel.z_index = 90
	# Start off-screen: shift offsets right by 140px
	panel.offset_left = 0.0
	panel.offset_right = 140.0
	add_child(panel)

	# VBox inside the panel to stack turn label + tracker
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# Move turn label into the vbox first
	turn_label_margin.get_parent().remove_child(turn_label_margin)
	vbox.add_child(turn_label_margin)

	# Move tracker into the vbox
	tracker.get_parent().remove_child(tracker)
	vbox.add_child(tracker)
	tracker.visible = true

	# Toggle button pinned to the right edge
	_mobile_tracker_toggle_btn = Button.new()
	_mobile_tracker_toggle_btn.text = tr("STR_GB_TURNS")
	_mobile_tracker_toggle_btn.custom_minimum_size = Vector2(50, 75)
	_mobile_tracker_toggle_btn.anchor_left = 1.0
	_mobile_tracker_toggle_btn.anchor_right = 1.0
	_mobile_tracker_toggle_btn.anchor_top = 0.5
	_mobile_tracker_toggle_btn.anchor_bottom = 0.5
	var trk_pad_r := maxf(4.0, _safe_right)
	_mobile_tracker_toggle_btn.offset_left = - (trk_pad_r + 50.0)
	_mobile_tracker_toggle_btn.offset_top = -38.0
	_mobile_tracker_toggle_btn.offset_right = - trk_pad_r
	_mobile_tracker_toggle_btn.offset_bottom = 37.0
	_mobile_tracker_toggle_btn.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mobile_tracker_toggle_btn.add_theme_font_size_override("font_size", 12)
	_mobile_tracker_toggle_btn.z_index = 91
	_mobile_tracker_toggle_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_tab_style(_mobile_tracker_toggle_btn, "right")
	_mobile_tracker_toggle_btn.pressed.connect(_toggle_mobile_tracker_tray)
	add_child(_mobile_tracker_toggle_btn)


func _toggle_mobile_tracker_tray() -> void:
	var panel := get_node_or_null("MobileTrackerPanel") as PanelContainer
	if not panel:
		return
	_mobile_tracker_tray_open = not _mobile_tracker_tray_open

	if _mobile_tracker_tween and _mobile_tracker_tween.is_valid():
		_mobile_tracker_tween.kill()
	_mobile_tracker_tween = create_tween()
	_mobile_tracker_tween.set_ease(Tween.EASE_OUT)
	_mobile_tracker_tween.set_trans(Tween.TRANS_CUBIC)

	var trk_pad := maxf(4.0, _safe_right)
	if _mobile_tracker_tray_open:
		# Slide panel on-screen: offsets go to normal position
		_mobile_tracker_tween.tween_property(panel, "offset_left", - (140.0 + trk_pad), 0.25)
		_mobile_tracker_tween.parallel().tween_property(panel, "offset_right", -trk_pad, 0.25)
		_mobile_tracker_tween.parallel().tween_property(_mobile_tracker_toggle_btn, "offset_left", - (190.0 + trk_pad), 0.25)
		_mobile_tracker_tween.parallel().tween_property(_mobile_tracker_toggle_btn, "offset_right", - (140.0 + trk_pad), 0.25)
	else:
		# Slide panel off-screen to the right
		_mobile_tracker_tween.tween_property(panel, "offset_left", 0.0, 0.25)
		_mobile_tracker_tween.parallel().tween_property(panel, "offset_right", 140.0, 0.25)
		_mobile_tracker_tween.parallel().tween_property(_mobile_tracker_toggle_btn, "offset_left", - (trk_pad + 50.0), 0.25)
		_mobile_tracker_tween.parallel().tween_property(_mobile_tracker_toggle_btn, "offset_right", -trk_pad, 0.25)


func _apply_safe_area_insets() -> void:
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size := DisplayServer.screen_get_size()
	if screen_size.x > 0 and screen_size.y > 0:
		var viewport_size := get_viewport().get_visible_rect().size
		var scale_x := viewport_size.x / float(screen_size.x)
		var scale_y := viewport_size.y / float(screen_size.y)
		_safe_left = safe_area.position.x * scale_x
		_safe_top = safe_area.position.y * scale_y
		_safe_right = (screen_size.x - (safe_area.position.x + safe_area.size.x)) * scale_x
		_safe_bottom = (screen_size.y - (safe_area.position.y + safe_area.size.y)) * scale_y
		var vbox := _board.get_node("VBoxContainer")
		vbox.offset_left = _safe_left
		vbox.offset_right = - _safe_right
		vbox.offset_top = _safe_top


func _retry_safe_area_insets() -> void:
	_apply_safe_area_insets()
	if _safe_left == 0.0 and _safe_right == 0.0 and _safe_top == 0.0:
		return # Still no safe area data — nothing to update
	# Reposition all floating elements with the now-available safe area insets
	var pad_l := maxf(20.0, _safe_left + 4.0)
	var pad_r := maxf(20.0, _safe_right + 4.0)
	var pad_b := maxf(20.0, _safe_bottom + 4.0)
	# FAB container
	if _fab_container:
		var btn_size := 85.0
		var col_gap := 12.0
		var label_h := 18.0
		var cell_h := btn_size + label_h + 2.0
		var row_gap := 8.0
		var grid_w := btn_size * 3 + col_gap * 2
		var container_w := grid_w + 20.0
		var container_h := cell_h * 2.0 + row_gap + btn_size + 8.0
		_fab_container.offset_left = - (pad_r + container_w)
		_fab_container.offset_right = - pad_r
		_fab_container.offset_top = - (pad_b + container_h)
		_fab_container.offset_bottom = - pad_b
		if _fab_main_btn:
			_fab_main_btn.position = Vector2(container_w - btn_size, container_h - btn_size)
	# Log toggle button
	var log_pad := maxf(4.0, _safe_left)
	if _mobile_log_toggle_btn:
		if not _mobile_log_tray_open:
			_mobile_log_toggle_btn.offset_left = log_pad
			_mobile_log_toggle_btn.offset_right = log_pad + 50.0
		else:
			_mobile_log_toggle_btn.offset_left = 320.0 + log_pad
			_mobile_log_toggle_btn.offset_right = 370.0 + log_pad
	# CP toggle button (above log button)
	if _mobile_cp_toggle_btn:
		if not _mobile_cp_tray_open:
			_mobile_cp_toggle_btn.offset_left = log_pad
			_mobile_cp_toggle_btn.offset_right = log_pad + 50.0
		else:
			_mobile_cp_toggle_btn.offset_left = _mobile_cp_panel_w + log_pad
			_mobile_cp_toggle_btn.offset_right = _mobile_cp_panel_w + 50.0 + log_pad
	# Board view toggle button — positioned dynamically in _position_hands()
	# Tracker toggle button
	var trk_pad := maxf(4.0, _safe_right)
	if _mobile_tracker_toggle_btn:
		if not _mobile_tracker_tray_open:
			_mobile_tracker_toggle_btn.offset_left = - (trk_pad + 50.0)
			_mobile_tracker_toggle_btn.offset_right = - trk_pad
		else:
			_mobile_tracker_toggle_btn.offset_left = - (190.0 + trk_pad)
			_mobile_tracker_toggle_btn.offset_right = - (140.0 + trk_pad)
	# Menu button + panel (top-right)
	if _mobile_menu_btn:
		var menu_pad := maxf(20.0, _safe_right + 4.0)
		var menu_pad_t := maxf(40.0, _safe_top + 24.0)
		_mobile_menu_btn.offset_left = - (menu_pad + 58.0)
		_mobile_menu_btn.offset_right = - menu_pad
		_mobile_menu_btn.offset_top = menu_pad_t
		_mobile_menu_btn.offset_bottom = menu_pad_t + 55.0
	if _mobile_menu_panel:
		var menu_pad2 := maxf(20.0, _safe_right + 4.0)
		var menu_pad_t2 := maxf(40.0, _safe_top + 24.0)
		var panel_top := menu_pad_t2 + 55.0 + 8.0
		_mobile_menu_panel.offset_left = - (menu_pad2 + 200.0)
		_mobile_menu_panel.offset_right = - menu_pad2
		_mobile_menu_panel.offset_top = panel_top
	# Phase label (top-right)
	if _mobile_phase_label:
		var phase_pad := maxf(60.0, _safe_right + 50.0)
		var phase_pad_t := maxf(20.0, _safe_top + 4.0)
		_mobile_phase_label.offset_right = - phase_pad
		_mobile_phase_label.offset_top = phase_pad_t
	# Action prompt — width capped at 25% via anchor_right
	var prompt := get_node_or_null("ActionPrompt") as PanelContainer
	if prompt:
		prompt.offset_left = pad_l
		prompt.offset_right = 0.0
	# Hand button stacks update via _position_hands
	_position_hands()


func _update_mobile_chat_bar() -> void:
	if _mobile_chat_bar == null or not _mobile_chat_bar.visible:
		return
	var kb_native := DisplayServer.virtual_keyboard_get_height()
	var kb_view := 0.0
	if kb_native > 0:
		var viewport_size := get_viewport().get_visible_rect().size
		var screen_size := DisplayServer.screen_get_size()
		kb_view = float(kb_native)
		if screen_size.y > 0:
			kb_view = kb_native * (viewport_size.y / float(screen_size.y))
	# The bar is anchored to the bottom edge; lift it by the keyboard height.
	if absf(_mobile_chat_bar_lift - kb_view) < 1.0:
		_mobile_chat_bar_lift = kb_view
	else:
		_mobile_chat_bar_lift = lerpf(_mobile_chat_bar_lift, kb_view, 0.3)
	_mobile_chat_bar.position.y = -_mobile_chat_bar_lift


func _toggle_fab() -> void:
	if _fab_expanded:
		_collapse_fab()
	else:
		_expand_fab()


func _expand_fab() -> void:
	if _fab_expanded:
		return
	_fab_expanded = true

	_fab_backdrop.visible = true
	_fab_backdrop.modulate.a = 0.0

	if _fab_tween and _fab_tween.is_valid():
		_fab_tween.kill()
	_fab_tween = create_tween()
	_fab_tween.set_parallel(true)

	# Fade in backdrop
	_fab_tween.tween_property(_fab_backdrop, "modulate:a", 1.0, 0.2)

	# Rotate FAB "+" to "×" (45°)
	_fab_tween.tween_property(_fab_main_btn, "rotation", deg_to_rad(45.0), 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	var btn_size := 85.0
	var fab_center := _fab_main_btn.position + Vector2(btn_size / 2.0, btn_size / 2.0)

	var count := _fab_action_btns.size()
	for i in range(count):
		var btn: Button = _fab_action_btns[i]
		var lbl: Label = _fab_labels[i]
		var target_pos: Vector2 = btn.get_meta("fab_target_pos")
		var stagger := (count - 1 - i) * 0.03

		btn.visible = true
		btn.position = fab_center - Vector2(btn_size / 2.0, btn_size / 2.0)
		btn.scale = Vector2.ZERO
		btn.custom_minimum_size = Vector2(btn_size, btn_size)
		btn.size = Vector2(btn_size, btn_size)
		btn.text = ""
		btn.pivot_offset = Vector2(btn_size / 2.0, btn_size / 2.0)
		_apply_circle_style(btn, Color(0.2, 0.3, 0.5, 0.9))

		_fab_tween.tween_property(btn, "position", target_pos, 0.25) \
			.set_delay(stagger) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_fab_tween.tween_property(btn, "scale", Vector2.ONE, 0.25) \
			.set_delay(stagger) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

		lbl.visible = true
		lbl.modulate.a = 0.0
		_fab_tween.tween_property(lbl, "modulate:a", 1.0, 0.15) \
			.set_delay(stagger + 0.15)

	# Hide standalone pills while FAB is expanded
	btn_end_main.visible = false
	btn_confirm.visible = false
	btn_cancel.visible = false

	_fab_main_btn.queue_redraw()

	# Controller: GamepadBoardNav jails its cursor onto the expanded grid
	# (row 0: Battle|Monster|Strategy, row 1: Rage|Invade — BoardNavGraph's
	# mobile edges); the buttons never take real focus.
	fab_toggled.emit(true)


func _collapse_fab() -> void:
	if not _fab_expanded:
		return
	_fab_expanded = false

	if _fab_tween and _fab_tween.is_valid():
		_fab_tween.kill()
	_fab_tween = create_tween()
	_fab_tween.set_parallel(true)

	_fab_tween.tween_property(_fab_backdrop, "modulate:a", 0.0, 0.15)
	_fab_tween.tween_property(_fab_main_btn, "rotation", 0.0, 0.2) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)

	var btn_size := 85.0
	var fab_center := _fab_main_btn.position + Vector2(btn_size / 2.0, btn_size / 2.0)

	var count := _fab_action_btns.size()
	for i in range(count):
		var btn: Button = _fab_action_btns[i]
		var lbl: Label = _fab_labels[i]
		var stagger := i * 0.02

		lbl.visible = false

		_fab_tween.tween_property(btn, "position",
			fab_center - Vector2(btn_size / 2.0, btn_size / 2.0), 0.2) \
			.set_delay(stagger) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_fab_tween.tween_property(btn, "scale", Vector2.ZERO, 0.2) \
			.set_delay(stagger) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	_fab_tween.chain().tween_callback(func():
		for btn: Button in _fab_action_btns:
			btn.visible = false
		_fab_backdrop.visible = false
		_setup_standalone_buttons()
		btn_end_main.visible = true
		btn_confirm.visible = true
		btn_cancel.visible = true
		fab_toggled.emit(false)
	)

	_fab_main_btn.queue_redraw()


func _collapse_fab_instant() -> void:
	if not _fab_expanded and not _fab_action_btns.is_empty() and not _fab_action_btns[0].visible:
		# Already collapsed — just ensure standalone button positions
		if _fab_container:
			_setup_standalone_buttons()
		return
	_fab_expanded = false
	if _fab_tween and _fab_tween.is_valid():
		_fab_tween.kill()
	for i in range(_fab_action_btns.size()):
		_fab_action_btns[i].visible = false
		_fab_action_btns[i].scale = Vector2.ZERO
		if i < _fab_labels.size():
			_fab_labels[i].visible = false
	if _fab_backdrop:
		_fab_backdrop.visible = false
	if _fab_main_btn:
		_fab_main_btn.rotation = 0.0
		_fab_main_btn.queue_redraw()
	_setup_standalone_buttons()
	btn_end_main.visible = true
	btn_confirm.visible = true
	btn_cancel.visible = true
	fab_toggled.emit(false)


func fab_expanded() -> bool:
	return _fab_expanded


## Idempotent tray control for the controller bumpers (LB = log, RB =
## tracker): open/close only when the state actually changes, reusing the
## exact toggle tweens the tab buttons drive.
func set_log_tray_open(open: bool) -> void:
	if _mobile_log_tray_open != open:
		_toggle_mobile_log_tray()


func is_log_tray_open() -> bool:
	return _mobile_log_tray_open


func set_tracker_tray_open(open: bool) -> void:
	if _mobile_tracker_tray_open != open:
		_toggle_mobile_tracker_tray()


func is_tracker_tray_open() -> bool:
	return _mobile_tracker_tray_open


func fab_main_button() -> Button:
	return _fab_main_btn


func fab_container() -> Control:
	return _fab_container


# Runtime-built chrome buttons, resolved by GamepadBoardNav._ui_button for
# the sys_* nav ids (mobile layout only).
func menu_button() -> Button:
	return _mobile_menu_btn


func cp_toggle_button() -> Button:
	return _mobile_cp_toggle_btn


func log_toggle_button() -> Button:
	return _mobile_log_toggle_btn


func tracker_toggle_button() -> Button:
	return _mobile_tracker_toggle_btn


func view_toggle_button() -> Button:
	return _mobile_view_toggle_btn


func _on_fab_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_collapse_fab()
		get_viewport().set_input_as_handled()


func _draw_btn_texture(btn: Button, tex: Texture2D) -> void:
	if not btn or not tex:
		return
	var s := btn.size
	var pad := 12.0
	var available := Vector2(s.x - pad * 2, s.y - pad * 2)
	var tex_size := tex.get_size()
	var tex_scale := minf(available.x / tex_size.x, available.y / tex_size.y)
	var draw_size := tex_size * tex_scale
	var pos := Vector2((s.x - draw_size.x) / 2.0, (s.y - draw_size.y) / 2.0)
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	btn.draw_texture_rect(tex, Rect2(pos, draw_size), false, color)


func _draw_fab_main_icon() -> void:
	var btn := _fab_main_btn
	if not btn:
		return
	var s := btn.size
	var cx := s.x / 2.0
	var cy := s.y / 2.0
	var arm := 10.0
	var color := Color.WHITE
	# "+" shape — rotation tween makes it look like "×" when expanded
	btn.draw_line(Vector2(cx - arm, cy), Vector2(cx + arm, cy), color, 3.0)
	btn.draw_line(Vector2(cx, cy - arm), Vector2(cx, cy + arm), color, 3.0)


func _draw_icon_battle(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var pad := 14.0
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	var w := 2.5
	# Crossed swords
	btn.draw_line(Vector2(pad, pad), Vector2(s.x - pad, s.y - pad), color, w)
	btn.draw_line(Vector2(s.x - pad, pad), Vector2(pad, s.y - pad), color, w)
	# Crossguards
	var t := (s.x - pad * 2) * 0.33
	var c1 := Vector2(pad + t, pad + t)
	btn.draw_line(c1 + Vector2(-4, 4), c1 + Vector2(4, -4), color, w)
	var c2 := Vector2(s.x - pad - t, pad + t)
	btn.draw_line(c2 + Vector2(-4, -4), c2 + Vector2(4, 4), color, w)


func _draw_icon_monster(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var cx := s.x / 2.0
	var cy := s.y / 2.0
	var outer_r := s.x / 2.0 - 14.0
	var inner_r := outer_r * 0.4
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	var points: PackedVector2Array = []
	for i in range(10):
		var angle := -PI / 2.0 + i * PI / 5.0
		var r := outer_r if i % 2 == 0 else inner_r
		points.append(Vector2(cx + cos(angle) * r, cy + sin(angle) * r))
	points.append(points[0])
	btn.draw_polyline(points, color, 2.0)


func _draw_icon_strategy(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var cx := s.x / 2.0
	var cy := s.y / 2.0
	var rx := s.x / 2.0 - 14.0
	var ry := s.y / 2.0 - 12.0
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	btn.draw_polyline(PackedVector2Array([
		Vector2(cx, cy - ry),
		Vector2(cx + rx, cy),
		Vector2(cx, cy + ry),
		Vector2(cx - rx, cy),
		Vector2(cx, cy - ry),
	]), color, 2.5)


func _draw_icon_end_main(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	var pad := 14.0
	# Checkmark
	btn.draw_line(Vector2(pad, s.y * 0.5), Vector2(s.x * 0.4, s.y - pad), color, 2.5)
	btn.draw_line(Vector2(s.x * 0.4, s.y - pad), Vector2(s.x - pad, pad), color, 2.5)


func _draw_icon_rage(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var cx := s.x / 2.0
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	var pad := 14.0
	# Up arrow
	btn.draw_line(Vector2(cx, s.y - pad), Vector2(cx, pad), color, 2.5)
	btn.draw_line(Vector2(cx, pad), Vector2(cx - 8, pad + 10), color, 2.5)
	btn.draw_line(Vector2(cx, pad), Vector2(cx + 8, pad + 10), color, 2.5)


func _draw_icon_invade(btn: Button) -> void:
	if not btn:
		return
	var s := btn.size
	var cy := s.y / 2.0
	var color := Color.WHITE if not btn.disabled else Color(0.6, 0.6, 0.6)
	var pad := 14.0
	# Right arrow
	btn.draw_line(Vector2(pad, cy), Vector2(s.x - pad, cy), color, 2.5)
	btn.draw_line(Vector2(s.x - pad, cy), Vector2(s.x - pad - 10, cy - 8), color, 2.5)
	btn.draw_line(Vector2(s.x - pad, cy), Vector2(s.x - pad - 10, cy + 8), color, 2.5)
