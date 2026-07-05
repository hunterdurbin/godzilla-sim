extends Control

const CARD_SCENE := preload("res://scenes/cards/Card.tscn")
const CARD_SCALE := 0.42
const CARD_SIZE := Vector2(150, 210)
const SCALED_SIZE := CARD_SIZE * CARD_SCALE
const ZOOM_MIN_COLUMNS := 5 # most zoomed in (largest cards)
const ZOOM_MAX_COLUMNS := 12 # most zoomed out (smallest cards)
const ZOOM_DEFAULT_COLUMNS := 7

# --- Left panel ---
var deck_name_edit: LineEdit
var deck_list_view: DeckListView
var save_button: Button
var load_button: Button
var delete_button: Button
var import_button: Button
var import_decklog_button: Button
var export_button: Button
var deck_stats_label: RichTextLabel
var validation_label: RichTextLabel
var back_button: Button
var format_option: OptionButton
var format_info_button: Button
var default_mode_check: CheckBox

# --- Right panel: deck section ---
var monster_tab_button: Button
var main_tab_button: Button
var deck_zoom_in_button: Button
var deck_zoom_out_button: Button
var pool_zoom_in_button: Button
var pool_zoom_out_button: Button
var deck_grid: GridContainer
var deck_scroll: ScrollContainer

# --- Right panel: filter bar ---
var search_edit: LineEdit
var type_buttons: Array[Button] = []
var color_buttons: Array[Button] = []
var invasion_buttons: Array[Button] = []
var sort_option: OptionButton

# --- Right panel: pool section ---
var pool_count_label: Label
var pool_grid: GridContainer
var pool_scroll: ScrollContainer

# --- Dialogs ---
var unsaved_dialog: ConfirmationDialog
var delete_dialog: ConfirmationDialog
var empty_save_dialog: ConfirmationDialog
var clear_dialog: ConfirmationDialog
var format_info_dialog: AcceptDialog
var format_info_body: VBoxContainer
var decklog_dialog: AcceptDialog
var decklog_url_edit: LineEdit
var decklog_region_btn: OptionButton
var decklog_import_btn: Button
var decklog_status_label: Label
var _decklog_importer: DecklogImporter

# --- State ---
var _monster_entries: Array = []
var _main_entries: Array = []
var _current_deck_name: String = ""
var _has_unsaved_changes: bool = false
var _showing_monster_tab: bool = true
var _deck_zoom_columns: int = ZOOM_DEFAULT_COLUMNS
var _pool_zoom_columns: int = ZOOM_DEFAULT_COLUMNS

var _all_pool_cards: Array[Dictionary] = []
var _filtered_pool_cards: Array[Dictionary] = []

var _search_text: String = ""
var _search_criteria: Array = [] # Parsed criteria from _search_text; each is a Dict
var _type_filter: int = -1 # -1 = all
var _color_filters: Array[int] = []
var _invasion_filter: int = -1 # -1 = all, 1 = step 1, 2 = step 2
var _sort_mode: int = 0 # 0=ID, 1=Name, 2=Rank, 3=Type

var _pending_action: Callable
var _invalid_cards: Dictionary = {} # card_number -> true
var _game_mode: String = "rumble_west"
var _pool_load_generation: int = 0 # Incremented to cancel stale batched loads

# --- Preview ---
var _preview_card: Control
var _search_timer: Timer


func _ready() -> void:
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.25
	_search_timer.timeout.connect(_on_search_debounce)
	add_child(_search_timer)

	_build_ui()
	_connect_signals()
	_build_pool_card_list()
	_refresh_deck_list()

	var saved_idx := _index_of_mode(GameSettings.default_game_mode)
	_game_mode = GameModeValidator.MODES[saved_idx]["id"]
	format_option.select(saved_idx)
	default_mode_check.set_pressed_no_signal(_game_mode == GameSettings.default_game_mode)

	_apply_filters()
	_refresh_pool_display()
	_refresh_deck_display()
	_update_deck_stats()
	_update_zoom_buttons()

	GamepadHelper.push_focus_context(self, _first_focusable)


func _exit_tree() -> void:
	GamepadHelper.pop_focus_context(self)


func _first_focusable() -> Control:
	# make_pad_focusable controls only become FOCUS_ALL in gamepad mode, so
	# resolve lazily at refocus time.
	var root: Control = self
	return _find_focusable(root)


func _find_focusable(node: Node) -> Control:
	if node is Control:
		var control := node as Control
		if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			return control
	for child in node.get_children():
		var found := _find_focusable(child)
		if found != null:
			return found
	return null


# ============================================================
# UI Construction
# ============================================================

func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.03, 0.02, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main layout
	var main_layout := HBoxContainer.new()
	main_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_layout.add_theme_constant_override("separation", 10)
	main_layout.offset_left = 10
	main_layout.offset_top = 10
	main_layout.offset_right = -10
	main_layout.offset_bottom = -10
	add_child(main_layout)

	_build_left_panel(main_layout)
	_build_right_panel(main_layout)
	_build_dialogs()

	# Card preview — fixed overlay, bottom-left, 1/3 viewport width
	_preview_card = CARD_SCENE.instantiate()
	_preview_card.drag_enabled = false
	_preview_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_card.visible = false
	_preview_card.z_index = 50
	add_child(_preview_card)
	get_tree().root.size_changed.connect(_position_preview)


func _build_left_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	_apply_panel_style(panel)
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = tr("STR_DB_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	vbox.add_child(title)

	# Deck name
	deck_name_edit = LineEdit.new()
	deck_name_edit.placeholder_text = tr("STR_DB_DECK_NAME")
	vbox.add_child(deck_name_edit)

	# Compact picker: selected deck preview + folder subtitle + Move to…
	# button. The full deck list lives behind the picker click (modal).
	deck_list_view = DeckListView.new()
	deck_list_view.compact = true
	deck_list_view.allow_move = true
	deck_list_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(deck_list_view)

	# Save / Load / Delete
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	vbox.add_child(btn_row)

	save_button = Button.new()
	save_button.text = tr("STR_DB_SAVE")
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(save_button)

	load_button = Button.new()
	load_button.text = tr("STR_DB_LOAD")
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(load_button)

	delete_button = Button.new()
	delete_button.text = tr("STR_DB_DELETE")
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(delete_button)

	vbox.add_child(HSeparator.new())

	# Clipboard buttons
	import_button = Button.new()
	import_button.text = tr("STR_DB_IMPORT")
	vbox.add_child(import_button)

	import_decklog_button = Button.new()
	import_decklog_button.text = tr("STR_DB_IMPORT_DECKLOG")
	vbox.add_child(import_decklog_button)

	export_button = Button.new()
	export_button.text = tr("STR_DB_EXPORT")
	vbox.add_child(export_button)

	vbox.add_child(HSeparator.new())

	# Deck stats row (stats label + format dropdown)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 8)
	stats_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(stats_row)

	deck_stats_label = RichTextLabel.new()
	deck_stats_label.bbcode_enabled = true
	deck_stats_label.custom_minimum_size.y = 60
	deck_stats_label.fit_content = true
	deck_stats_label.scroll_active = false
	deck_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_row.add_child(deck_stats_label)

	var format_col := VBoxContainer.new()
	format_col.add_theme_constant_override("separation", 4)
	format_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stats_row.add_child(format_col)

	var format_row := HBoxContainer.new()
	format_row.add_theme_constant_override("separation", 4)
	format_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	format_col.add_child(format_row)

	format_info_button = Button.new()
	format_info_button.text = "i"
	format_info_button.tooltip_text = tr("STR_DB_FORMAT_INFO_TOOLTIP")
	format_info_button.custom_minimum_size = Vector2(28, 28)
	GamepadHelper.make_pad_focusable(format_info_button)
	format_row.add_child(format_info_button)

	format_option = OptionButton.new()
	format_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(GameModeValidator.MODES.size()):
		format_option.add_item(tr(GameModeValidator.MODES[i]["label"]), i)
	format_row.add_child(format_option)

	default_mode_check = CheckBox.new()
	default_mode_check.text = tr("STR_DB_SET_AS_DEFAULT")
	default_mode_check.add_theme_font_size_override("font_size", 14)
	format_col.add_child(default_mode_check)

	# Validation (scrollable, fixed height)
	var validation_scroll := ScrollContainer.new()
	validation_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	validation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	validation_scroll.scroll_deadzone = 20
	validation_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(validation_scroll)

	validation_label = RichTextLabel.new()
	validation_label.bbcode_enabled = true
	validation_label.fit_content = true
	validation_label.scroll_active = false
	validation_label.mouse_filter = Control.MOUSE_FILTER_PASS
	validation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	validation_scroll.add_child(validation_label)

	# Back button
	back_button = Button.new()
	back_button.text = tr("STR_DB_BACK")
	back_button.custom_minimum_size.y = 40
	vbox.add_child(back_button)


func _build_right_panel(parent: HBoxContainer) -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2.0
	right.add_theme_constant_override("separation", 5)
	parent.add_child(right)

	_build_deck_section(right)
	_build_filter_bar(right)
	_build_pool_section(right)


func _build_deck_section(parent: VBoxContainer) -> void:
	var section := VBoxContainer.new()
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.size_flags_stretch_ratio = 0.4
	parent.add_child(section)

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	section.add_child(header)

	var label := Label.new()
	label.text = tr("STR_DB_DECK")
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	header.add_child(label)

	monster_tab_button = Button.new()
	monster_tab_button.text = tr("STR_TYPE_MONSTER")
	monster_tab_button.toggle_mode = true
	monster_tab_button.button_pressed = true
	header.add_child(monster_tab_button)

	main_tab_button = Button.new()
	main_tab_button.text = tr("STR_DB_TAB_MAIN")
	main_tab_button.toggle_mode = true
	header.add_child(main_tab_button)

	deck_zoom_out_button = _make_zoom_button("−", "Zoom out deck")
	header.add_child(deck_zoom_out_button)

	deck_zoom_in_button = _make_zoom_button("+", "Zoom in deck")
	header.add_child(deck_zoom_in_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)

	var clear_button := Button.new()
	clear_button.text = tr("STR_COMMON_CLEAR")
	clear_button.pressed.connect(_on_clear_pressed)
	header.add_child(clear_button)

	# Scroll + grid
	deck_scroll = ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	deck_scroll.scroll_deadzone = 20
	deck_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	section.add_child(deck_scroll)

	deck_grid = GridContainer.new()
	deck_grid.columns = _deck_zoom_columns
	deck_grid.add_theme_constant_override("h_separation", 4)
	deck_grid.add_theme_constant_override("v_separation", 4)
	deck_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	deck_scroll.add_child(deck_grid)


func _build_filter_bar(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	_apply_panel_style(panel)
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	# Search
	search_edit = LineEdit.new()
	search_edit.placeholder_text = tr("STR_DB_SEARCH_PLACEHOLDER")
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.custom_minimum_size.x = 150
	hbox.add_child(search_edit)

	# Type filter buttons
	var type_box := HBoxContainer.new()
	type_box.add_theme_constant_override("separation", 2)
	hbox.add_child(type_box)

	var type_name_keys := ["STR_DB_FILTER_ALL", "STR_TYPE_MONSTER", "STR_TYPE_BATTLE", "STR_TYPE_STRATEGY"]
	for i in range(type_name_keys.size()):
		var btn := Button.new()
		btn.text = tr(type_name_keys[i])
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)
		btn.add_theme_font_size_override("font_size", 12)
		type_box.add_child(btn)
		type_buttons.append(btn)

	# Separator
	hbox.add_child(VSeparator.new())

	# Color filter buttons
	var color_box := HBoxContainer.new()
	color_box.add_theme_constant_override("separation", 2)
	hbox.add_child(color_box)

	var color_values := [
		CardEnums.CardColor.RED,
		CardEnums.CardColor.BLUE,
		CardEnums.CardColor.WHITE,
		CardEnums.CardColor.GREEN,
	]
	for i in range(color_values.size()):
		var btn := Button.new()
		btn.text = CardEnums.color_to_string(color_values[i])
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", CardEnums.color_to_godot_color(color_values[i]))
		color_box.add_child(btn)
		color_buttons.append(btn)

	# Separator
	hbox.add_child(VSeparator.new())

	# Invasion icon filter buttons
	var invasion_box := HBoxContainer.new()
	invasion_box.add_theme_constant_override("separation", 2)
	hbox.add_child(invasion_box)

	var inv_name_keys := ["STR_DB_INVASION_STEP1", "STR_DB_INVASION_STEP2"]
	for i in range(inv_name_keys.size()):
		var btn := Button.new()
		btn.text = tr(inv_name_keys[i])
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", 12)
		invasion_box.add_child(btn)
		invasion_buttons.append(btn)

	# Separator
	hbox.add_child(VSeparator.new())

	# Sort
	sort_option = OptionButton.new()
	sort_option.add_item(tr("STR_DB_SORT_ID"), 0)
	sort_option.add_item(tr("STR_DB_SORT_NAME"), 1)
	sort_option.add_item(tr("STR_DB_SORT_RANK"), 2)
	sort_option.add_item(tr("STR_DB_SORT_TYPE"), 3)
	sort_option.add_theme_font_size_override("font_size", 12)
	hbox.add_child(sort_option)


func _build_pool_section(parent: VBoxContainer) -> void:
	var section := VBoxContainer.new()
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.size_flags_stretch_ratio = 0.6
	parent.add_child(section)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	section.add_child(header)

	var label := Label.new()
	label.text = tr("STR_DB_CARD_POOL")
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	header.add_child(label)

	pool_count_label = Label.new()
	pool_count_label.add_theme_font_size_override("font_size", 14)
	pool_count_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.5, 1))
	header.add_child(pool_count_label)

	pool_zoom_out_button = _make_zoom_button("−", "Zoom out pool")
	header.add_child(pool_zoom_out_button)

	pool_zoom_in_button = _make_zoom_button("+", "Zoom in pool")
	header.add_child(pool_zoom_in_button)

	# Scroll + grid
	pool_scroll = ScrollContainer.new()
	pool_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pool_scroll.scroll_deadzone = 20
	pool_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	section.add_child(pool_scroll)

	pool_grid = GridContainer.new()
	pool_grid.columns = _pool_zoom_columns
	pool_grid.add_theme_constant_override("h_separation", 4)
	pool_grid.add_theme_constant_override("v_separation", 4)
	pool_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	pool_scroll.add_child(pool_grid)


func _build_dialogs() -> void:
	unsaved_dialog = ConfirmationDialog.new()
	unsaved_dialog.title = tr("STR_DB_UNSAVED_TITLE")
	unsaved_dialog.dialog_text = tr("STR_DB_UNSAVED_TEXT")
	unsaved_dialog.ok_button_text = tr("STR_DB_UNSAVED_DISCARD")
	unsaved_dialog.cancel_button_text = tr("STR_COMMON_CANCEL")
	add_child(unsaved_dialog)

	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = tr("STR_DB_DELETE_TITLE")
	delete_dialog.ok_button_text = tr("STR_DB_DELETE_OK")
	delete_dialog.cancel_button_text = tr("STR_COMMON_CANCEL")
	add_child(delete_dialog)

	empty_save_dialog = ConfirmationDialog.new()
	empty_save_dialog.title = tr("STR_DB_EMPTY_SAVE_TITLE")
	empty_save_dialog.dialog_text = tr("STR_DB_EMPTY_SAVE_TEXT")
	empty_save_dialog.ok_button_text = tr("STR_DB_EMPTY_SAVE_OK")
	empty_save_dialog.cancel_button_text = tr("STR_COMMON_CANCEL")
	add_child(empty_save_dialog)

	clear_dialog = ConfirmationDialog.new()
	clear_dialog.title = tr("STR_DB_CLEAR_TITLE")
	clear_dialog.dialog_text = tr("STR_DB_CLEAR_TEXT")
	clear_dialog.ok_button_text = tr("STR_COMMON_CLEAR")
	clear_dialog.cancel_button_text = tr("STR_COMMON_CANCEL")
	add_child(clear_dialog)

	format_info_dialog = AcceptDialog.new()
	format_info_dialog.min_size = Vector2(560, 540)
	var info_scroll := ScrollContainer.new()
	info_scroll.custom_minimum_size = Vector2(520, 480)
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	format_info_dialog.add_child(info_scroll)

	format_info_body = VBoxContainer.new()
	format_info_body.add_theme_constant_override("separation", 8)
	format_info_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(format_info_body)
	add_child(format_info_dialog)

	decklog_dialog = AcceptDialog.new()
	decklog_dialog.title = tr("STR_DB_DECKLOG_TITLE")
	decklog_dialog.dialog_hide_on_ok = false
	decklog_dialog.get_ok_button().hide()
	decklog_dialog.add_cancel_button(tr("STR_COMMON_CANCEL"))
	var decklog_vbox := VBoxContainer.new()
	decklog_vbox.add_theme_constant_override("separation", 8)
	decklog_vbox.custom_minimum_size = Vector2(500, 0)
	decklog_dialog.add_child(decklog_vbox)

	var decklog_helper := Label.new()
	decklog_helper.text = tr("STR_DB_DECKLOG_HELPER")
	decklog_vbox.add_child(decklog_helper)

	var url_row := HBoxContainer.new()
	url_row.add_theme_constant_override("separation", 8)
	decklog_vbox.add_child(url_row)

	decklog_url_edit = LineEdit.new()
	decklog_url_edit.placeholder_text = tr("STR_DB_DECKLOG_PLACEHOLDER")
	decklog_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_row.add_child(decklog_url_edit)

	decklog_region_btn = OptionButton.new()
	decklog_region_btn.add_item("EN", 0)
	decklog_region_btn.add_item("JP", 1)
	decklog_region_btn.selected = 0
	decklog_region_btn.tooltip_text = tr("STR_DB_DECKLOG_REGION_TOOLTIP")
	url_row.add_child(decklog_region_btn)

	var decklog_row := HBoxContainer.new()
	decklog_row.add_theme_constant_override("separation", 8)
	decklog_vbox.add_child(decklog_row)

	decklog_status_label = Label.new()
	decklog_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decklog_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	decklog_row.add_child(decklog_status_label)

	decklog_import_btn = Button.new()
	decklog_import_btn.text = tr("STR_DB_DECKLOG_FETCH")
	decklog_row.add_child(decklog_import_btn)

	add_child(decklog_dialog)


func _apply_panel_style(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.06, 0.9)
	style.border_color = Color(0.9, 0.3, 0.1, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)


# ============================================================
# Signal Connections
# ============================================================

func _connect_signals() -> void:
	# Left panel
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	import_button.pressed.connect(_on_import_pressed)
	import_decklog_button.pressed.connect(_on_import_decklog_pressed)
	export_button.pressed.connect(_on_export_pressed)
	decklog_import_btn.pressed.connect(_on_decklog_fetch_pressed)
	decklog_url_edit.text_submitted.connect(func(_t): _on_decklog_fetch_pressed())
	decklog_dialog.about_to_popup.connect(_prefill_decklog_input)
	back_button.pressed.connect(_on_back_pressed)
	deck_list_view.deck_selected.connect(_on_deck_list_selected)
	deck_list_view.deck_activated.connect(_load_deck)
	deck_name_edit.text_changed.connect(_on_deck_name_text_changed)

	# Deck tabs
	monster_tab_button.pressed.connect(_on_monster_tab_pressed)
	main_tab_button.pressed.connect(_on_main_tab_pressed)
	deck_zoom_in_button.pressed.connect(_on_deck_zoom_in_pressed)
	deck_zoom_out_button.pressed.connect(_on_deck_zoom_out_pressed)
	pool_zoom_in_button.pressed.connect(_on_pool_zoom_in_pressed)
	pool_zoom_out_button.pressed.connect(_on_pool_zoom_out_pressed)

	# Filters
	search_edit.text_changed.connect(_on_search_changed)
	for i in range(type_buttons.size()):
		type_buttons[i].pressed.connect(_on_type_button_pressed.bind(i))
	for i in range(color_buttons.size()):
		color_buttons[i].pressed.connect(_on_color_button_pressed.bind(i))
	for i in range(invasion_buttons.size()):
		invasion_buttons[i].pressed.connect(_on_invasion_button_pressed.bind(i))
	sort_option.item_selected.connect(_on_sort_changed)
	format_option.item_selected.connect(_on_format_changed)
	format_info_button.pressed.connect(_show_format_info)
	default_mode_check.toggled.connect(_on_default_mode_toggled)

	# Dialogs
	unsaved_dialog.confirmed.connect(_on_unsaved_confirmed)
	delete_dialog.confirmed.connect(_on_delete_confirmed)
	empty_save_dialog.confirmed.connect(_on_empty_save_confirmed)
	clear_dialog.confirmed.connect(_on_clear_confirmed)


# ============================================================
# Card Pool
# ============================================================

func _build_pool_card_list() -> void:
	_all_pool_cards.clear()
	for card_id in CardData.CARD_TEMPLATES:
		var card: Dictionary = CardData.CARD_TEMPLATES[card_id]
		if card.get("card_type") == CardEnums.CardType.RAGE:
			continue
		_all_pool_cards.append(card)
	_all_pool_cards.sort_custom(_sort_by_id)


static func _is_token(card_data: Dictionary) -> bool:
	var traits: Array = card_data.get("traits", [])
	return CardEnums.CardTrait.TOKEN in traits


func _apply_filters() -> void:
	_filtered_pool_cards.clear()
	for card in _all_pool_cards:
		if _card_matches_filters(card):
			_filtered_pool_cards.append(card)
	_sort_pool()


func _card_matches_filters(card: Dictionary) -> bool:
	# Game mode card pool — hides cards outside the active format's pool.
	# No-rules mode accepts every card.
	if not GameModeValidator.is_card_valid_for_mode(card.get("id", ""), _game_mode):
		return false

	# Type filter
	if _type_filter >= 0 and card.get("card_type", -1) != _type_filter:
		return false

	# Color filter
	if not _color_filters.is_empty():
		var card_colors: Array = card.get("colors", [])
		var has_match := false
		for c in _color_filters:
			if c in card_colors:
				has_match = true
				break
		if not has_match:
			return false

	# Invasion icon filter
	if _invasion_filter > 0:
		if card.get("invasion_icon", 0) != _invasion_filter:
			return false

	# Text search — comma-separated criteria (AND); each is either a numeric
	# comparison (e.g. cp>1000, r=3, >1000) or a fuzzy text match.
	for criterion in _search_criteria:
		if not _card_matches_search_criterion(card, criterion):
			return false

	return true


# --- Search parsing & matching ---

const _SEARCH_FIELD_ALIASES := {
	"c": "cp", "cp": "cp", "counter": "cp", "power": "cp", "counterpower": "cp",
	"t": "threat", "threat": "threat", "level": "threat", "threatlevel": "threat",
	"r": "rank", "rank": "rank",
}

const _SEARCH_NUMERIC_FIELDS := ["cp", "threat", "rank"]


static func _parse_search_criteria(raw: String) -> Array:
	## Split on commas; parse each as either a numeric compare or fuzzy text.
	## A leading `!` negates the criterion (exclude matching cards).
	var criteria: Array = []
	for chunk in raw.split(","):
		var token: String = chunk.strip_edges().to_lower()
		if token.is_empty():
			continue
		var negate: bool = token.begins_with("!")
		if negate:
			token = token.substr(1).strip_edges()
			if token.is_empty():
				continue
		var compare := _try_parse_compare(token)
		var entry: Dictionary
		if not compare.is_empty():
			entry = compare
		else:
			entry = {"type": "fuzzy", "needle": token}
		entry["negate"] = negate
		criteria.append(entry)
	return criteria


static func _try_parse_compare(token: String) -> Dictionary:
	## Match `[field][op][int]`. op ∈ {>=, <=, !=, ==, =, >, <}. Field is
	## optional; if omitted, the comparison is checked against any numeric field
	## (cp, threat, rank). Returns {} if the token isn't a valid compare.
	var ops := [">=", "<=", "!=", "==", "=", ">", "<"]
	var op_str := ""
	var op_pos := -1
	for op in ops:
		var p := token.find(op)
		if p >= 0:
			op_str = op
			op_pos = p
			break
	if op_pos < 0:
		return {}
	var lhs := token.substr(0, op_pos).strip_edges().replace(" ", "").replace("_", "")
	var rhs := token.substr(op_pos + op_str.length()).strip_edges()
	if not rhs.is_valid_int():
		return {}
	var field := "any"
	if not lhs.is_empty():
		if not _SEARCH_FIELD_ALIASES.has(lhs):
			return {}
		field = _SEARCH_FIELD_ALIASES[lhs]
	# Normalize "==" → "=" for downstream.
	if op_str == "==":
		op_str = "="
	return {"type": "compare", "field": field, "op": op_str, "value": rhs.to_int()}


func _card_matches_search_criterion(card: Dictionary, criterion: Dictionary) -> bool:
	var matched: bool = _evaluate_criterion(card, criterion)
	if criterion.get("negate", false):
		return not matched
	return matched


func _evaluate_criterion(card: Dictionary, criterion: Dictionary) -> bool:
	match criterion.get("type", ""):
		"compare":
			var field: String = criterion.get("field", "any")
			var op: String = criterion.get("op", "=")
			var value: int = criterion.get("value", 0)
			if field == "any":
				for f in _SEARCH_NUMERIC_FIELDS:
					if not _card_has_field(card, f):
						continue
					if _compare_int(_card_field(card, f), op, value):
						return true
				return false
			if not _card_has_field(card, field):
				return false
			return _compare_int(_card_field(card, field), op, value)
		"fuzzy":
			return _card_matches_fuzzy(card, criterion.get("needle", ""))
	return false


static func _card_has_field(card: Dictionary, field: String) -> bool:
	match field:
		"cp": return card.has("counter_power")
		"threat": return card.has("threat_level")
		"rank": return card.has("rank")
	return false


static func _card_field(card: Dictionary, field: String) -> int:
	match field:
		"cp": return card.get("counter_power", 0)
		"threat": return card.get("threat_level", 0)
		"rank": return card.get("rank", 0)
	return 0


static func _compare_int(lhs: int, op: String, rhs: int) -> bool:
	match op:
		">": return lhs > rhs
		"<": return lhs < rhs
		">=": return lhs >= rhs
		"<=": return lhs <= rhs
		"=": return lhs == rhs
		"!=": return lhs != rhs
	return false


func _card_matches_fuzzy(card: Dictionary, needle: String) -> bool:
	## Substring match across name, id, description, traits, and common names.
	if card.get("name", "").to_lower().contains(needle):
		return true
	if card.get("id", "").to_lower().contains(needle):
		return true
	if card.get("description", "").to_lower().contains(needle):
		return true
	for t in CardData.get_printed_field(card, "traits", CardData.printing_for_mode(_game_mode), []):
		if CardEnums.trait_to_string(t).to_lower().contains(needle):
			return true
	for cn in card.get("common_names", []):
		if String(cn).to_lower().contains(needle):
			return true
	return false


func _sort_pool() -> void:
	match _sort_mode:
		0: _filtered_pool_cards.sort_custom(_sort_by_id)
		1: _filtered_pool_cards.sort_custom(_sort_by_name)
		2: _filtered_pool_cards.sort_custom(_sort_by_rank)
		3: _filtered_pool_cards.sort_custom(_sort_by_type)


func _sort_by_id(a: Dictionary, b: Dictionary) -> bool:
	return a.get("id", "") < b.get("id", "")

func _sort_by_name(a: Dictionary, b: Dictionary) -> bool:
	var na: String = a.get("name", "")
	var nb: String = b.get("name", "")
	if na != nb:
		return na < nb
	return a.get("id", "") < b.get("id", "")

func _sort_by_rank(a: Dictionary, b: Dictionary) -> bool:
	var ra: int = a.get("rank", 0)
	var rb: int = b.get("rank", 0)
	if ra != rb:
		return ra < rb
	return a.get("id", "") < b.get("id", "")

func _sort_by_type(a: Dictionary, b: Dictionary) -> bool:
	var ta: int = a.get("card_type", 0)
	var tb: int = b.get("card_type", 0)
	if ta != tb:
		return ta < tb
	return a.get("id", "") < b.get("id", "")


# ============================================================
# Display: Pool
# ============================================================

const POOL_BATCH_SIZE := 15

func _refresh_pool_display() -> void:
	_clear_grid(pool_grid)
	_pool_load_generation += 1
	var gen := _pool_load_generation
	pool_count_label.text = tr("STR_DB_POOL_COUNT_FMT").replace("{N}", str(_filtered_pool_cards.size()))
	# Snapshot the list so filter changes mid-load don't cause issues
	var cards_to_load := _filtered_pool_cards.duplicate()
	_load_pool_cards_batched(cards_to_load, gen)


func _load_pool_cards_batched(cards: Array[Dictionary], gen: int) -> void:
	var i := 0
	while i < cards.size():
		if gen != _pool_load_generation:
			return # A newer refresh was triggered; abort this one
		var batch_end := mini(i + POOL_BATCH_SIZE, cards.size())
		while i < batch_end:
			var wrapper := _create_card_wrapper(cards[i], true)
			pool_grid.add_child(wrapper)
			i += 1
		if i < cards.size():
			await get_tree().process_frame
			if not is_inside_tree():
				return


func _update_pool_badge(card_id: String) -> void:
	for wrapper in pool_grid.get_children():
		var card_node: Control = wrapper.get_child(0)
		if card_node.card_data.get("id", "") != card_id:
			continue
		if _is_token(card_node.card_data):
			break
		# Remove old badge if present
		for child in wrapper.get_children():
			if child is Label:
				child.queue_free()
		# Update modulate and add new badge
		var count := _get_card_count_in_deck(card_id)
		var max_copies := _get_max_copies(card_node.card_data)
		var at_max: bool = count >= max_copies and _game_mode != "no_rules"
		card_node.modulate = Color(0.5, 0.5, 0.5, 0.7) if at_max else Color.WHITE
		if count > 0:
			var badge := _create_badge("%d/%d" % [count, max_copies])
			wrapper.add_child(badge)
		break


func _create_card_wrapper(card_data: Dictionary, is_pool: bool, deck_qty: int = 0) -> PanelContainer:
	var wrapper := PanelContainer.new()
	wrapper.custom_minimum_size = SCALED_SIZE
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	var card_id: String = card_data.get("id", "")
	var style := StyleBoxEmpty.new()
	wrapper.add_theme_stylebox_override("panel", style)

	var card_node: Control = CARD_SCENE.instantiate()
	card_node.use_custom_art = false
	card_node.skip_effect_load = true
	card_node.set_card_data_dict(card_data)
	card_node.drag_enabled = false
	card_node.custom_minimum_size = Vector2.ZERO
	card_node.scale = Vector2(CARD_SCALE, CARD_SCALE)
	card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(card_node)
	# Re-scale card to fit wrapper when it resizes, maintaining aspect ratio
	wrapper.resized.connect(func():
		var s: float = wrapper.size.x / CARD_SIZE.x
		card_node.scale = Vector2(s, s)
		wrapper.custom_minimum_size.y = CARD_SIZE.y * s
	)

	# Handle clicks on the wrapper since the card ignores mouse input
	var parent_scroll: ScrollContainer = pool_scroll if is_pool else deck_scroll
	var click_handler := func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if TouchHelper.is_touch_device():
				# Touch: fire click on release, only if finger didn't scroll
				if event.pressed:
					wrapper.set_meta("_press_pos", event.global_position)
					wrapper.set_meta("_scroll_v", parent_scroll.scroll_vertical)
				else:
					var press_pos: Vector2 = wrapper.get_meta("_press_pos", event.global_position)
					var prev_scroll: int = wrapper.get_meta("_scroll_v", parent_scroll.scroll_vertical)
					var scrolled := parent_scroll.scroll_vertical != prev_scroll
					if not scrolled and event.global_position.distance_to(press_pos) < 20:
						if is_pool:
							_on_pool_card_clicked(card_node)
						else:
							_on_deck_card_clicked(card_node)
			else:
				if event.pressed:
					if is_pool:
						_on_pool_card_clicked(card_node)
					else:
						_on_deck_card_clicked(card_node)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not is_pool:
			_on_deck_card_right_clicked(card_node)
	wrapper.gui_input.connect(click_handler)

	# Card preview on hover
	wrapper.mouse_entered.connect(func(): _show_preview(card_data, is_pool))
	wrapper.mouse_exited.connect(_hide_preview)

	# Quantity badge
	if is_pool:
		if _is_token(card_data):
			card_node.modulate = Color(0.5, 0.5, 0.5, 0.7)
			var badge := _create_badge("Token")
			wrapper.add_child(badge)
		else:
			var count := _get_card_count_in_deck(card_data.get("id", ""))
			var max_copies := _get_max_copies(card_data)
			if count > 0:
				var badge := _create_badge("%d/%d" % [count, max_copies])
				wrapper.add_child(badge)
				if count >= max_copies and _game_mode != "no_rules":
					card_node.modulate = Color(0.5, 0.5, 0.5, 0.7)
	else:
		var is_monster_type: bool = card_data.get("card_type", -1) == CardEnums.CardType.MONSTER
		var in_monster: bool = not _showing_monster_tab and _is_in_monster_deck(card_id)

		# Quantity / +M badge
		if deck_qty > 1 or in_monster:
			var badge_text := "x%d" % deck_qty if deck_qty > 1 else ""
			if in_monster:
				badge_text += " +M" if not badge_text.is_empty() else "+M"
			var badge := _create_badge(badge_text)
			wrapper.add_child(badge)

		# Move button for monster-type cards in deck (shown on hover)
		if is_monster_type:
			var btn_layer := Control.new()
			btn_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var move_btn := Button.new()
			move_btn.add_theme_font_size_override("font_size", 8)
			move_btn.add_theme_color_override("font_color", Color.WHITE)
			move_btn.position = Vector2(1, SCALED_SIZE.y * 0.5 - 8)
			move_btn.z_index = 10
			move_btn.visible = false
			if _showing_monster_tab:
				move_btn.text = tr("STR_DB_TO_MAIN")
				move_btn.pressed.connect(_move_monster_to_main.bind(card_id))
			elif in_monster:
				move_btn.text = tr("STR_DB_TO_MAIN")
				move_btn.pressed.connect(_move_monster_to_main.bind(card_id))
			else:
				move_btn.text = tr("STR_DB_TO_MONSTER")
				move_btn.pressed.connect(_move_monster_to_monster.bind(card_id))
			btn_layer.add_child(move_btn)
			wrapper.add_child(btn_layer)
			# Show immediately if mouse is already over the card
			wrapper.ready.connect(func():
				if wrapper.get_global_rect().has_point(wrapper.get_global_mouse_position()):
					move_btn.visible = true
			, CONNECT_ONE_SHOT)
			var _hide_if_outside := func() -> void:
				if not wrapper.get_global_rect().has_point(wrapper.get_global_mouse_position()):
					move_btn.visible = false
			wrapper.mouse_entered.connect(func(): move_btn.visible = true)
			wrapper.mouse_exited.connect(_hide_if_outside)
			move_btn.mouse_exited.connect(_hide_if_outside)

	# Red border overlay for invalid cards
	if not is_pool and card_id in _invalid_cards:
		var border := Panel.new()
		border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var border_style := StyleBoxFlat.new()
		border_style.bg_color = Color.TRANSPARENT
		border_style.border_color = Color(1, 0.2, 0.1, 0.9)
		border_style.set_border_width_all(2)
		border_style.set_corner_radius_all(3)
		border.add_theme_stylebox_override("panel", border_style)
		wrapper.add_child(border)

	return wrapper


func _create_badge(text: String) -> Label:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge.offset_right = -4
	badge.offset_bottom = -4
	# Background for readability
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.7)
	bg.set_corner_radius_all(3)
	bg.set_content_margin_all(2)
	badge.add_theme_stylebox_override("normal", bg)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge


# ============================================================
# Preview
# ============================================================

var _preview_is_strategy: bool = false


func _show_preview(card_data: Dictionary, _from_pool: bool) -> void:
	_preview_is_strategy = card_data.get("card_type", -1) == CardEnums.CardType.STRATEGY
	_preview_card.set_card_data_dict(card_data)
	_preview_card.visible = true
	_position_preview()


func _position_preview() -> void:
	if not _preview_card.visible:
		return
	var vp: Vector2 = get_viewport_rect().size
	var target_w: float = vp.x / 3.0
	# Pivot is center of 150x210 card
	# Godot transform: screen(L) = pos + pivot + R(s*(L - pivot))
	# Visual bounding box edges derived from corner transforms:

	if _preview_is_strategy:
		# Rotated -90: visual width = 210*s, visual height = 150*s
		var s: float = target_w / CARD_SIZE.y
		if CARD_SIZE.x * s > vp.y:
			s = vp.y / CARD_SIZE.x
		_preview_card.scale = Vector2(s, s)
		_preview_card.rotation = - PI / 2.0
		_preview_card.position.x = 105.0 * s - 75.0
		_preview_card.position.y = 75.0 * s - 105.0
	else:
		# No rotation: visual width = 150*s, visual height = 210*s
		var s: float = target_w / CARD_SIZE.x
		if CARD_SIZE.y * s > vp.y:
			s = vp.y / CARD_SIZE.y
		_preview_card.scale = Vector2(s, s)
		_preview_card.rotation = 0.0
		_preview_card.position.x = 75.0 * s - 75.0
		_preview_card.position.y = 105.0 * s - 105.0


func _hide_preview() -> void:
	_preview_card.visible = false
	_preview_card.rotation = 0.0


# ============================================================
# Display: Deck
# ============================================================

func _refresh_deck_display() -> void:
	_clear_grid(deck_grid)
	_invalid_cards = GameModeValidator.get_invalid_cards(_game_mode, _monster_entries, _main_entries)
	var entries: Array = _monster_entries if _showing_monster_tab else _main_entries
	for entry in entries:
		var card_data: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		if card_data.is_empty():
			continue
		var wrapper := _create_card_wrapper(card_data, false, entry["quantity"])
		deck_grid.add_child(wrapper)

	# Update tab buttons
	monster_tab_button.button_pressed = _showing_monster_tab
	main_tab_button.button_pressed = not _showing_monster_tab


func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		child.queue_free()


# ============================================================
# Add / Remove Cards
# ============================================================

func _on_pool_card_clicked(card_node: Control) -> void:
	var card_data: Dictionary = card_node.card_data
	var card_id: String = card_data.get("id", "")

	if _is_token(card_data):
		return

	if _showing_monster_tab:
		if card_data.get("card_type", -1) != CardEnums.CardType.MONSTER:
			return
		var displaced_id := _add_to_monster_deck(card_id)
		_has_unsaved_changes = true
		_refresh_deck_display()
		_update_pool_badge(card_id)
		if not displaced_id.is_empty() and displaced_id != card_id:
			_update_pool_badge(displaced_id)
	else:
		_add_to_main_deck(card_id)
		_has_unsaved_changes = true
		_refresh_deck_display()
		_update_pool_badge(card_id)

	_update_deck_stats()


func _on_deck_card_clicked(card_node: Control) -> void:
	var card_data: Dictionary = card_node.card_data
	var card_id: String = card_data.get("id", "")

	if _showing_monster_tab:
		_remove_from_monster_deck(card_id)
	else:
		_remove_from_main_deck(card_id)

	_has_unsaved_changes = true
	_refresh_deck_display()
	_update_pool_badge(card_id)
	_update_deck_stats()


func _on_deck_card_right_clicked(card_node: Control) -> void:
	var card_data: Dictionary = card_node.card_data
	var card_id: String = card_data.get("id", "")

	if _showing_monster_tab:
		_remove_from_monster_deck(card_id)
	else:
		_remove_all_from_main_deck(card_id)

	_has_unsaved_changes = true
	_refresh_deck_display()
	_update_pool_badge(card_id)
	_update_deck_stats()


func _add_to_monster_deck(card_id: String) -> String:
	var template: Dictionary = CardData.CARD_TEMPLATES.get(card_id, {})
	if template.is_empty():
		return ""
	var rank: int = template.get("rank", 0)
	# Replace existing card at same rank
	for entry in _monster_entries:
		var existing: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		if existing.get("rank", 0) == rank:
			var displaced_id: String = entry["card_number"]
			entry["card_number"] = card_id
			_sort_monster_entries()
			return displaced_id
	if _monster_entries.size() >= 4:
		return ""
	_monster_entries.append({"card_number": card_id, "quantity": 1})
	_sort_monster_entries()
	return ""


func _add_to_main_deck(card_id: String) -> void:
	if _game_mode != "no_rules":
		var count := _get_card_count_in_deck(card_id)
		var template: Dictionary = CardData.CARD_TEMPLATES.get(card_id, {})
		var max_copies := _get_max_copies(template)
		if count >= max_copies:
			return
		if _get_main_deck_total() >= 50:
			return
		if template.get("invasion_icon", 0) >= 2 and _get_step2_count() >= 10:
			return

	for entry in _main_entries:
		if entry["card_number"] == card_id:
			entry["quantity"] += 1
			return
	_main_entries.append({"card_number": card_id, "quantity": 1})
	_sort_main_entries()


func _remove_from_monster_deck(card_id: String) -> void:
	_monster_entries = _monster_entries.filter(
		func(e): return e["card_number"] != card_id
	)


func _remove_from_main_deck(card_id: String) -> void:
	for i in range(_main_entries.size()):
		if _main_entries[i]["card_number"] == card_id:
			_main_entries[i]["quantity"] -= 1
			if _main_entries[i]["quantity"] <= 0:
				_main_entries.remove_at(i)
			return


func _remove_all_from_main_deck(card_id: String) -> void:
	_main_entries = _main_entries.filter(
		func(e): return e["card_number"] != card_id
	)


func _move_monster_to_main(card_id: String) -> void:
	_remove_from_monster_deck(card_id)
	_add_to_main_deck(card_id)
	_has_unsaved_changes = true
	_refresh_deck_display()
	_update_pool_badge(card_id)
	_update_deck_stats()


func _move_monster_to_monster(card_id: String) -> void:
	var template: Dictionary = CardData.CARD_TEMPLATES.get(card_id, {})
	if template.is_empty():
		return
	var rank: int = template.get("rank", 0)
	# If a monster of the same rank exists, swap it to main
	var displaced_id := ""
	for entry in _monster_entries:
		var existing: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		if existing.get("rank", 0) == rank:
			displaced_id = entry["card_number"]
			break
	# Remove one copy from main deck
	_remove_from_main_deck(card_id)
	# If displacing, remove from monster and add displaced to main
	if not displaced_id.is_empty():
		_remove_from_monster_deck(displaced_id)
		_add_to_main_deck(displaced_id)
	# Add to monster deck
	_monster_entries.append({"card_number": card_id, "quantity": 1})
	_sort_monster_entries()
	_has_unsaved_changes = true
	_refresh_deck_display()
	_update_pool_badge(card_id)
	if not displaced_id.is_empty():
		_update_pool_badge(displaced_id)
	_update_deck_stats()


func _sort_main_entries() -> void:
	_main_entries.sort_custom(func(a, b):
		var ta: Dictionary = CardData.CARD_TEMPLATES.get(a["card_number"], {})
		var tb: Dictionary = CardData.CARD_TEMPLATES.get(b["card_number"], {})
		var type_a: int = ta.get("card_type", 0)
		var type_b: int = tb.get("card_type", 0)
		if type_a != type_b:
			return type_a < type_b
		var rank_a: int = ta.get("rank", 0)
		var rank_b: int = tb.get("rank", 0)
		if rank_a != rank_b:
			return rank_a < rank_b
		return a["card_number"] < b["card_number"]
	)


func _sort_monster_entries() -> void:
	_monster_entries.sort_custom(func(a, b):
		var ra: int = CardData.CARD_TEMPLATES.get(a["card_number"], {}).get("rank", 0)
		var rb: int = CardData.CARD_TEMPLATES.get(b["card_number"], {}).get("rank", 0)
		return ra < rb
	)


# ============================================================
# Helpers
# ============================================================

func _is_in_monster_deck(card_id: String) -> bool:
	var base_id: String = card_id.trim_suffix("+")
	for entry in _monster_entries:
		if entry["card_number"].trim_suffix("+") == base_id:
			return true
	return false

func _get_card_count_in_deck(card_id: String) -> int:
	var base_id: String = card_id.trim_suffix("+")
	var count := 0
	for entry in _monster_entries:
		if entry["card_number"].trim_suffix("+") == base_id:
			count += entry["quantity"]
	for entry in _main_entries:
		if entry["card_number"].trim_suffix("+") == base_id:
			count += entry["quantity"]
	return count


func _get_entry_quantity(card_id: String) -> int:
	for entry in _monster_entries:
		if entry["card_number"] == card_id:
			return entry["quantity"]
	for entry in _main_entries:
		if entry["card_number"] == card_id:
			return entry["quantity"]
	return 0


func _get_main_deck_total() -> int:
	var total := 0
	for entry in _main_entries:
		total += entry["quantity"]
	return total


func _get_step2_count() -> int:
	var count := 0
	for entry in _main_entries:
		var t: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		if t.get("invasion_icon", 0) >= 2:
			count += entry["quantity"]
	return count


func _get_max_copies(card_data: Dictionary) -> int:
	if card_data.get("unlimited_copies", false):
		return 50
	return 4


# ============================================================
# Deck Stats & Validation
# ============================================================

func _update_deck_stats() -> void:
	var monster_count := _monster_entries.size()
	var main_count := _get_main_deck_total()
	var step2_count := _get_step2_count()

	var mc := "[color=green]" if monster_count == 4 else "[color=yellow]"
	var mnc := "[color=green]" if main_count == 50 else "[color=yellow]"
	var sc := "[color=green]" if step2_count <= 10 else "[color=red]"

	var text := ""
	text += "[b]%s[/b] %s%d / 4[/color]\n" % [tr("STR_DB_MONSTER_DECK"), mc, monster_count]
	text += "[b]%s[/b] %s%d / 50[/color]\n" % [tr("STR_DB_MAIN_DECK"), mnc, main_count]
	text += "[b]%s[/b] %s%d / 10[/color]" % [tr("STR_DB_STEP2_CARDS"), sc, step2_count]
	deck_stats_label.clear()
	deck_stats_label.append_text(text)

	_update_validation()


func _update_validation() -> void:
	validation_label.clear()
	var errors := GameModeValidator.validate(_game_mode, _monster_entries, _main_entries)
	var warnings: Array[String] = []
	if _game_mode != "no_rules":
		warnings = DeckValidator.warnings(_monster_entries, _main_entries)

	if not errors.is_empty():
		validation_label.append_text("[color=red][b]%s[/b][/color]\n" % tr("STR_DB_ERRORS"))
		for err in errors:
			validation_label.append_text("[color=red]- %s[/color]\n" % err)
	if not warnings.is_empty():
		validation_label.append_text("[color=yellow][b]%s[/b][/color]\n" % tr("STR_DB_WARNINGS"))
		for warn in warnings:
			validation_label.append_text("[color=yellow]- %s[/color]\n" % warn)


# ============================================================
# Deck Tab Switching
# ============================================================

func _on_monster_tab_pressed() -> void:
	SfxManager.play("ui_click")
	_showing_monster_tab = true
	_refresh_deck_display()


func _on_main_tab_pressed() -> void:
	SfxManager.play("ui_click")
	_showing_monster_tab = false
	_refresh_deck_display()


func _make_zoom_button(label: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(28, 28)
	GamepadHelper.make_pad_focusable(btn)
	return btn


func _on_deck_zoom_in_pressed() -> void:
	_set_deck_zoom_columns(_deck_zoom_columns - 1)


func _on_deck_zoom_out_pressed() -> void:
	_set_deck_zoom_columns(_deck_zoom_columns + 1)


func _on_pool_zoom_in_pressed() -> void:
	_set_pool_zoom_columns(_pool_zoom_columns - 1)


func _on_pool_zoom_out_pressed() -> void:
	_set_pool_zoom_columns(_pool_zoom_columns + 1)


func _set_deck_zoom_columns(cols: int) -> void:
	cols = clamp(cols, ZOOM_MIN_COLUMNS, ZOOM_MAX_COLUMNS)
	if cols == _deck_zoom_columns:
		_update_zoom_buttons()
		return
	SfxManager.play("ui_click")
	_deck_zoom_columns = cols
	deck_grid.columns = _deck_zoom_columns
	_update_zoom_buttons()
	_refresh_deck_display()


func _set_pool_zoom_columns(cols: int) -> void:
	cols = clamp(cols, ZOOM_MIN_COLUMNS, ZOOM_MAX_COLUMNS)
	if cols == _pool_zoom_columns:
		_update_zoom_buttons()
		return
	SfxManager.play("ui_click")
	_pool_zoom_columns = cols
	pool_grid.columns = _pool_zoom_columns
	_update_zoom_buttons()
	_refresh_pool_display()


func _update_zoom_buttons() -> void:
	deck_zoom_in_button.disabled = _deck_zoom_columns <= ZOOM_MIN_COLUMNS
	deck_zoom_out_button.disabled = _deck_zoom_columns >= ZOOM_MAX_COLUMNS
	pool_zoom_in_button.disabled = _pool_zoom_columns <= ZOOM_MIN_COLUMNS
	pool_zoom_out_button.disabled = _pool_zoom_columns >= ZOOM_MAX_COLUMNS


# ============================================================
# Filter Handlers
# ============================================================

func _on_search_changed(new_text: String) -> void:
	_search_text = new_text.strip_edges().to_lower()
	_search_criteria = _parse_search_criteria(_search_text)
	_search_timer.start()


func _on_search_debounce() -> void:
	_apply_filters()
	_refresh_pool_display()


func _on_type_button_pressed(index: int) -> void:
	# Radio-style: pressing one untoggles others
	if index == 0:
		# "All" button
		_type_filter = -1
		type_buttons[0].button_pressed = true
		for i in range(1, type_buttons.size()):
			type_buttons[i].button_pressed = false
	else:
		type_buttons[0].button_pressed = false
		# Untoggle other specific type buttons
		for i in range(1, type_buttons.size()):
			if i != index:
				type_buttons[i].button_pressed = false
		if type_buttons[index].button_pressed:
			match index:
				1: _type_filter = CardEnums.CardType.MONSTER
				2: _type_filter = CardEnums.CardType.BATTLE
				3: _type_filter = CardEnums.CardType.STRATEGY
		else:
			# Untoggled the active one — go back to All
			_type_filter = -1
			type_buttons[0].button_pressed = true

	_apply_filters()
	_refresh_pool_display()


func _on_color_button_pressed(_index: int) -> void:
	# Additive toggle
	_color_filters.clear()
	var color_values := [
		CardEnums.CardColor.RED,
		CardEnums.CardColor.BLUE,
		CardEnums.CardColor.WHITE,
		CardEnums.CardColor.GREEN,
	]
	for i in range(color_buttons.size()):
		if color_buttons[i].button_pressed:
			_color_filters.append(color_values[i])
	_apply_filters()
	_refresh_pool_display()


func _on_invasion_button_pressed(index: int) -> void:
	# Radio-style: only one can be active, pressing active one deselects
	var step := index + 1 # 0 → step 1, 1 → step 2
	if _invasion_filter == step:
		_invasion_filter = -1
		invasion_buttons[index].button_pressed = false
	else:
		_invasion_filter = step
		for i in range(invasion_buttons.size()):
			invasion_buttons[i].button_pressed = (i == index)
	_apply_filters()
	_refresh_pool_display()


func _on_sort_changed(index: int) -> void:
	_sort_mode = index
	_apply_filters()
	_refresh_pool_display()


func _on_format_changed(index: int) -> void:
	_game_mode = GameModeValidator.MODES[index]["id"]
	default_mode_check.set_pressed_no_signal(_game_mode == GameSettings.default_game_mode)
	_apply_filters()
	_refresh_pool_display()
	_refresh_deck_display()
	_update_deck_stats()


func _on_default_mode_toggled(pressed: bool) -> void:
	SfxManager.play("ui_click")
	if pressed:
		GameSettings.default_game_mode = _game_mode
	else:
		GameSettings.default_game_mode = "rumble_west"
	GameSettings.save()


func _index_of_mode(mode_id: String) -> int:
	for i in range(GameModeValidator.MODES.size()):
		if GameModeValidator.MODES[i]["id"] == mode_id:
			return i
	return 0


# ============================================================
# Format Info Modal
# ============================================================

func _show_format_info() -> void:
	SfxManager.play("ui_click")
	_populate_format_info(_game_mode)
	format_info_dialog.popup_centered()


func _populate_format_info(mode_id: String) -> void:
	for child in format_info_body.get_children():
		child.queue_free()

	var mode := GameModeValidator.get_mode(mode_id)
	if mode.is_empty():
		return

	format_info_dialog.title = tr("STR_DB_FORMAT_INFO_TITLE_FMT") % tr(mode.get("label", ""))

	_add_info_heading(tr("STR_DB_FORMAT_INFO_DESCRIPTION"))
	_add_info_paragraph(tr(mode.get("desc", "")))

	if not mode.has("card_pool"):
		_add_info_paragraph(tr("STR_DB_FORMAT_INFO_ALL_ALLOWED"))
		return

	var pool: Dictionary = mode["card_pool"]

	var sets: Array = pool.get("include_sets", [])
	if not sets.is_empty():
		_add_info_heading(tr("STR_DB_FORMAT_INFO_INCLUDED_SETS"))
		var packed := PackedStringArray()
		for s in sets:
			packed.append(s)
		_add_info_paragraph(", ".join(packed))

	var includes: Array = pool.get("include_cards", [])
	if not includes.is_empty():
		_add_info_heading(tr("STR_DB_FORMAT_INFO_INCLUDED_CARDS"))
		_add_info_paragraph(tr("STR_DB_FORMAT_INFO_INCLUDED_CARDS_SUMMARY_FMT") % includes.size())

	var excludes: Array = pool.get("exclude_cards", [])
	if not excludes.is_empty():
		_add_info_heading(tr("STR_DB_FORMAT_INFO_EXCLUDED_CARDS"))
		_add_info_paragraph(_format_card_list(excludes))

	var restricted: Array = pool.get("restricted", [])
	if not restricted.is_empty():
		_add_info_heading(tr("STR_DB_FORMAT_INFO_RESTRICTED"))
		_add_info_paragraph(tr("STR_DB_FORMAT_INFO_RESTRICTED_RULE"))
		_add_info_paragraph(_format_card_list(restricted))

	var pairs: Array = pool.get("choice_restricted", [])
	if not pairs.is_empty():
		_add_info_heading(tr("STR_DB_FORMAT_INFO_CHOICE_RESTRICTED"))
		_add_info_paragraph(tr("STR_DB_FORMAT_INFO_CHOICE_RULE"))
		var lines := PackedStringArray()
		for pair in pairs:
			lines.append("%s  ⇄  %s" % [_format_card_line(pair[0]), _format_card_line(pair[1])])
		_add_info_paragraph("\n".join(lines))


func _add_info_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	format_info_body.add_child(label)


func _add_info_paragraph(text: String) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = text
	format_info_body.add_child(label)


func _format_card_list(card_ids: Array) -> String:
	var lines := PackedStringArray()
	for cid in card_ids:
		lines.append(_format_card_line(cid))
	return "\n".join(lines)


func _format_card_line(card_id: String) -> String:
	var key := "CARD_%s_NAME" % card_id
	var translated := TranslationServer.translate(key)
	var card_name: String
	if translated != key:
		card_name = translated
	else:
		card_name = CardData.CARD_TEMPLATES.get(card_id, {}).get("name", card_id)
	return "%s · %s" % [card_id, card_name]


# ============================================================
# Save / Load / Delete
# ============================================================

func _on_save_pressed() -> void:
	SfxManager.play("ui_click")
	var deck_name := deck_name_edit.text.strip_edges()
	if deck_name.is_empty():
		deck_name_edit.grab_focus()
		return
	# Guard: saving an empty deck on top of an existing name silently wipes it.
	# Prompt first; only proceed on confirm.
	if _monster_entries.is_empty() and _main_entries.is_empty():
		empty_save_dialog.popup_centered()
		return
	_perform_save(deck_name)


func _on_empty_save_confirmed() -> void:
	var deck_name := deck_name_edit.text.strip_edges()
	if deck_name.is_empty():
		return
	_perform_save(deck_name)


func _perform_save(deck_name: String) -> void:
	# New decks adopt the last-loaded deck's folder (else root); existing decks
	# keep their current folder via DecklistManager's default behavior.
	var target_folder := ""
	if not _current_deck_name.is_empty() and _current_deck_name != deck_name:
		target_folder = DecklistManager.get_deck_folder(_current_deck_name)
	DecklistManager.save_decklist(deck_name, _monster_entries, _main_entries, target_folder)
	_current_deck_name = deck_name
	_has_unsaved_changes = false
	deck_list_view.refresh()
	deck_list_view.select_deck(deck_name)


func _on_load_pressed() -> void:
	SfxManager.play("ui_click")
	var deck_name := deck_list_view.get_selected_deck()
	if deck_name.is_empty():
		return
	if _has_unsaved_changes:
		_pending_action = _load_deck.bind(deck_name)
		unsaved_dialog.popup_centered()
		return
	_load_deck(deck_name)


func _load_deck(deck_name: String) -> void:
	var data: Dictionary = DecklistManager.load_decklist(deck_name)
	if data.is_empty():
		return
	_monster_entries = data["monster"].duplicate(true)
	_main_entries = data["main"].duplicate(true)
	_sort_monster_entries()
	_sort_main_entries()
	_current_deck_name = deck_name
	deck_name_edit.text = deck_name
	_has_unsaved_changes = false
	_showing_monster_tab = true
	_refresh_deck_display()
	_refresh_pool_display()
	_update_deck_stats()


func _on_deck_list_selected(deck_name: String) -> void:
	deck_name_edit.text = deck_name


func _on_deck_name_text_changed(new_text: String) -> void:
	var trimmed := new_text.strip_edges()
	if trimmed.is_empty():
		deck_list_view.clear_selection()
		return
	if trimmed in DecklistManager.get_all_decklists():
		deck_list_view.select_deck(trimmed)
	else:
		deck_list_view.clear_selection()


func _on_delete_pressed() -> void:
	SfxManager.play("ui_click")
	var deck_name := deck_list_view.get_selected_deck()
	if deck_name.is_empty():
		return
	delete_dialog.dialog_text = tr("STR_DB_DELETE_PROMPT") % deck_name
	delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	var deck_name := deck_list_view.get_selected_deck()
	if deck_name.is_empty():
		return
	DecklistManager.delete_decklist(deck_name)
	deck_list_view.clear_selection()
	deck_list_view.refresh()


func _on_clear_pressed() -> void:
	SfxManager.play("ui_click")
	if _monster_entries.is_empty() and _main_entries.is_empty():
		return
	clear_dialog.popup_centered()


func _on_clear_confirmed() -> void:
	_monster_entries.clear()
	_main_entries.clear()
	_has_unsaved_changes = true
	_refresh_deck_display()
	_refresh_pool_display()
	_update_deck_stats()


func _refresh_deck_list() -> void:
	deck_list_view.refresh()


# ============================================================
# Clipboard
# ============================================================

func _on_import_pressed() -> void:
	SfxManager.play("ui_click")
	var clipboard := DisplayServer.clipboard_get()
	if clipboard.strip_edges().is_empty():
		validation_label.clear()
		validation_label.append_text("[color=red]Clipboard is empty.[/color]")
		return
	if _has_unsaved_changes:
		_pending_action = _import_from_clipboard
		unsaved_dialog.popup_centered()
		return
	_import_from_clipboard()


func _import_from_clipboard() -> void:
	var clipboard := DisplayServer.clipboard_get()
	var data := DecklistManager._parse_decklist(clipboard)
	if data["monster"].is_empty() and data["main"].is_empty():
		validation_label.clear()
		validation_label.append_text("[color=red]Could not parse decklist from clipboard.[/color]")
		return
	_monster_entries = data["monster"]
	_main_entries = data["main"]
	_sort_monster_entries()
	_sort_main_entries()
	_has_unsaved_changes = true
	_showing_monster_tab = true
	_refresh_deck_display()
	_refresh_pool_display()
	_update_deck_stats()


func _on_import_decklog_pressed() -> void:
	SfxManager.play("ui_click")
	if _has_unsaved_changes:
		_pending_action = _open_decklog_dialog
		unsaved_dialog.popup_centered()
		return
	_open_decklog_dialog()


func _open_decklog_dialog() -> void:
	decklog_dialog.popup_centered(Vector2(520, 180))


func _prefill_decklog_input() -> void:
	decklog_url_edit.editable = true
	decklog_import_btn.disabled = false
	decklog_status_label.text = ""
	var clip := DisplayServer.clipboard_get().strip_edges()
	var parsed := DecklogImporter.parse_input(clip) if not clip.is_empty() else {}
	if not parsed.is_empty():
		decklog_url_edit.text = clip
		# If the clipboard was a full URL, sync the region toggle to its host.
		if parsed.get("host") == DecklogImporter.HOST_JP and clip.contains("://"):
			decklog_region_btn.selected = 1
		elif parsed.get("host") == DecklogImporter.HOST_EN and clip.contains("://"):
			decklog_region_btn.selected = 0
	else:
		decklog_url_edit.text = ""
	decklog_url_edit.call_deferred("grab_focus")


func _on_decklog_fetch_pressed() -> void:
	var raw := decklog_url_edit.text
	var host := _selected_decklog_host()
	if DecklogImporter.parse_input(raw, host).is_empty():
		_show_decklog_status(DecklogImporter.ERR_BAD_INPUT, {})
		return
	if _decklog_importer == null:
		_decklog_importer = DecklogImporter.new()
		add_child(_decklog_importer)
		_decklog_importer.completed.connect(_on_decklog_result)
	decklog_import_btn.disabled = true
	decklog_url_edit.editable = false
	decklog_status_label.modulate = Color.WHITE
	decklog_status_label.text = tr("STR_DB_DECKLOG_FETCHING")
	_decklog_importer.fetch(raw, host)


func _selected_decklog_host() -> String:
	return DecklogImporter.HOST_JP if decklog_region_btn.selected == 1 else DecklogImporter.HOST_EN


func _on_decklog_result(success: bool, payload: Dictionary, error_key: String) -> void:
	decklog_import_btn.disabled = false
	decklog_url_edit.editable = true
	if not success:
		_show_decklog_status(error_key, payload)
		return
	decklog_dialog.hide()
	_apply_decklog_payload(payload)


func _show_decklog_status(error_key: String, payload: Dictionary) -> void:
	var msg := tr(error_key)
	if error_key.ends_with("_FMT") and payload.has("game_title_id"):
		msg = msg % int(payload["game_title_id"])
	decklog_status_label.modulate = Color(1.0, 0.45, 0.45)
	decklog_status_label.text = msg


func _apply_decklog_payload(payload: Dictionary) -> void:
	_monster_entries = payload["monster_entries"]
	_main_entries = payload["main_entries"]
	_sort_monster_entries()
	_sort_main_entries()
	_has_unsaved_changes = true
	_showing_monster_tab = true
	if deck_name_edit.text.strip_edges().is_empty():
		deck_name_edit.text = String(payload.get("title", ""))
	_refresh_deck_display()
	_refresh_pool_display()
	_update_deck_stats()


func _on_export_pressed() -> void:
	SfxManager.play("ui_click")
	var text := "[monster deck]\n"
	for entry in _monster_entries:
		text += "%d %s\n" % [entry["quantity"], entry["card_number"]]
	text += "\n[main deck]\n"
	for entry in _main_entries:
		text += "%d %s\n" % [entry["quantity"], entry["card_number"]]
	DisplayServer.clipboard_set(text)
	# Brief feedback
	export_button.text = tr("STR_DB_COPIED")
	get_tree().create_timer(1.5).timeout.connect(func(): export_button.text = tr("STR_DB_EXPORT"))


# ============================================================
# Navigation
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_back_pressed() -> void:
	SfxManager.play("ui_click")
	if _has_unsaved_changes:
		_pending_action = _go_to_menu
		unsaved_dialog.popup_centered()
		return
	_go_to_menu()


func _go_to_menu() -> void:
	NetworkManager.change_scene("res://scenes/menus/MainMenu.tscn")


func _on_unsaved_confirmed() -> void:
	if _pending_action.is_valid():
		_pending_action.call()
		_pending_action = Callable()
