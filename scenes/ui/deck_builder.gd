extends Control

const CARD_SCENE := preload("res://scenes/cards/Card.tscn")
const CARD_SCALE := 0.42
const CARD_SIZE := Vector2(150, 210)
const SCALED_SIZE := CARD_SIZE * CARD_SCALE
const GRID_COLUMNS := 7

# --- Left panel ---
var deck_name_edit: LineEdit
var deck_list: ItemList
var save_button: Button
var load_button: Button
var delete_button: Button
var import_button: Button
var export_button: Button
var deck_stats_label: RichTextLabel
var validation_label: RichTextLabel
var back_button: Button

# --- Right panel: deck section ---
var monster_tab_button: Button
var main_tab_button: Button
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

# --- State ---
var _monster_entries: Array = []
var _main_entries: Array = []
var _current_deck_name: String = ""
var _has_unsaved_changes: bool = false
var _showing_monster_tab: bool = true

var _all_pool_cards: Array[Dictionary] = []
var _filtered_pool_cards: Array[Dictionary] = []

var _search_text: String = ""
var _type_filter: int = -1  # -1 = all
var _color_filters: Array[int] = []
var _invasion_filter: int = -1  # -1 = all, 1 = step 1, 2 = step 2
var _sort_mode: int = 0  # 0=ID, 1=Name, 2=Rank, 3=Type

var _pending_action: Callable
var _invalid_cards: Dictionary = {} # card_number -> true
var _pool_load_generation: int = 0  # Incremented to cancel stale batched loads

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
	_apply_filters()
	_refresh_pool_display()
	_refresh_deck_display()
	_update_deck_stats()


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
	title.text = "DECK BUILDER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	vbox.add_child(title)

	# Deck name
	deck_name_edit = LineEdit.new()
	deck_name_edit.placeholder_text = "Deck Name"
	vbox.add_child(deck_name_edit)

	# Deck list
	deck_list = ItemList.new()
	deck_list.custom_minimum_size.y = 120
	deck_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(deck_list)

	# Save / Load / Delete
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	vbox.add_child(btn_row)

	save_button = Button.new()
	save_button.text = "Save"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(save_button)

	load_button = Button.new()
	load_button.text = "Load"
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(load_button)

	delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(delete_button)

	vbox.add_child(HSeparator.new())

	# Clipboard buttons
	import_button = Button.new()
	import_button.text = "Import from Clipboard"
	vbox.add_child(import_button)

	export_button = Button.new()
	export_button.text = "Export to Clipboard"
	vbox.add_child(export_button)

	vbox.add_child(HSeparator.new())

	# Deck stats (fixed height)
	deck_stats_label = RichTextLabel.new()
	deck_stats_label.bbcode_enabled = true
	deck_stats_label.custom_minimum_size.y = 60
	deck_stats_label.fit_content = true
	deck_stats_label.scroll_active = false
	deck_stats_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(deck_stats_label)

	# Validation (scrollable, fixed height)
	var validation_scroll := ScrollContainer.new()
	validation_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	validation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(validation_scroll)

	validation_label = RichTextLabel.new()
	validation_label.bbcode_enabled = true
	validation_label.fit_content = true
	validation_label.scroll_active = false
	validation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	validation_scroll.add_child(validation_label)

	# Back button
	back_button = Button.new()
	back_button.text = "Back to Menu"
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
	label.text = "DECK"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	header.add_child(label)

	monster_tab_button = Button.new()
	monster_tab_button.text = "Monster"
	monster_tab_button.toggle_mode = true
	monster_tab_button.button_pressed = true
	header.add_child(monster_tab_button)

	main_tab_button = Button.new()
	main_tab_button.text = "Main"
	main_tab_button.toggle_mode = true
	header.add_child(main_tab_button)

	# Scroll + grid
	deck_scroll = ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	section.add_child(deck_scroll)

	deck_grid = GridContainer.new()
	deck_grid.columns = GRID_COLUMNS
	deck_grid.add_theme_constant_override("h_separation", 4)
	deck_grid.add_theme_constant_override("v_separation", 4)
	deck_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	search_edit.placeholder_text = "Search cards..."
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.custom_minimum_size.x = 150
	hbox.add_child(search_edit)

	# Type filter buttons
	var type_box := HBoxContainer.new()
	type_box.add_theme_constant_override("separation", 2)
	hbox.add_child(type_box)

	var type_names := ["All", "Monster", "Battle", "Strategy"]
	for i in range(type_names.size()):
		var btn := Button.new()
		btn.text = type_names[i]
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
	var color_names := ["Red", "Blue", "White", "Green"]
	for i in range(color_names.size()):
		var btn := Button.new()
		btn.text = color_names[i]
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

	var inv_names := ["Step 1", "Step 2"]
	for i in range(inv_names.size()):
		var btn := Button.new()
		btn.text = inv_names[i]
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", 12)
		invasion_box.add_child(btn)
		invasion_buttons.append(btn)

	# Separator
	hbox.add_child(VSeparator.new())

	# Sort
	sort_option = OptionButton.new()
	sort_option.add_item("Sort: ID", 0)
	sort_option.add_item("Sort: Name", 1)
	sort_option.add_item("Sort: Rank", 2)
	sort_option.add_item("Sort: Type", 3)
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
	label.text = "CARD POOL"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	header.add_child(label)

	pool_count_label = Label.new()
	pool_count_label.add_theme_font_size_override("font_size", 14)
	pool_count_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.5, 1))
	header.add_child(pool_count_label)

	# Scroll + grid
	pool_scroll = ScrollContainer.new()
	pool_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	section.add_child(pool_scroll)

	pool_grid = GridContainer.new()
	pool_grid.columns = GRID_COLUMNS
	pool_grid.add_theme_constant_override("h_separation", 4)
	pool_grid.add_theme_constant_override("v_separation", 4)
	pool_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_scroll.add_child(pool_grid)


func _build_dialogs() -> void:
	unsaved_dialog = ConfirmationDialog.new()
	unsaved_dialog.title = "Unsaved Changes"
	unsaved_dialog.dialog_text = "You have unsaved changes. Discard and continue?"
	unsaved_dialog.ok_button_text = "Discard"
	add_child(unsaved_dialog)

	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete Deck"
	delete_dialog.ok_button_text = "Delete"
	add_child(delete_dialog)


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
	export_button.pressed.connect(_on_export_pressed)
	back_button.pressed.connect(_on_back_pressed)
	deck_list.item_selected.connect(_on_deck_list_selected)

	# Deck tabs
	monster_tab_button.pressed.connect(_on_monster_tab_pressed)
	main_tab_button.pressed.connect(_on_main_tab_pressed)

	# Filters
	search_edit.text_changed.connect(_on_search_changed)
	for i in range(type_buttons.size()):
		type_buttons[i].pressed.connect(_on_type_button_pressed.bind(i))
	for i in range(color_buttons.size()):
		color_buttons[i].pressed.connect(_on_color_button_pressed.bind(i))
	for i in range(invasion_buttons.size()):
		invasion_buttons[i].pressed.connect(_on_invasion_button_pressed.bind(i))
	sort_option.item_selected.connect(_on_sort_changed)

	# Dialogs
	unsaved_dialog.confirmed.connect(_on_unsaved_confirmed)
	delete_dialog.confirmed.connect(_on_delete_confirmed)


# ============================================================
# Card Pool
# ============================================================

func _build_pool_card_list() -> void:
	_all_pool_cards.clear()
	for card_id in CardData.CARD_TEMPLATES:
		var card: Dictionary = CardData.CARD_TEMPLATES[card_id]
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

	# Text search
	if not _search_text.is_empty():
		var name_str: String = card.get("name", "").to_lower()
		var id_str: String = card.get("id", "").to_lower()
		var desc_str: String = card.get("description", "").to_lower()
		var trait_text := ""
		for t in card.get("traits", []):
			trait_text += CardEnums.trait_to_string(t).to_lower() + " "
		if not (name_str.contains(_search_text) or id_str.contains(_search_text)
				or desc_str.contains(_search_text) or trait_text.contains(_search_text)):
			return false

	return true


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
	pool_count_label.text = "(%d cards)" % _filtered_pool_cards.size()
	# Snapshot the list so filter changes mid-load don't cause issues
	var cards_to_load := _filtered_pool_cards.duplicate()
	_load_pool_cards_batched(cards_to_load, gen)


func _load_pool_cards_batched(cards: Array[Dictionary], gen: int) -> void:
	var i := 0
	while i < cards.size():
		if gen != _pool_load_generation:
			return  # A newer refresh was triggered; abort this one
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
		card_node.modulate = Color(0.5, 0.5, 0.5, 0.7) if count >= max_copies else Color.WHITE
		if count > 0:
			var badge := _create_badge("%d/%d" % [count, max_copies])
			wrapper.add_child(badge)
		break


func _create_card_wrapper(card_data: Dictionary, is_pool: bool, deck_qty: int = 0) -> PanelContainer:
	var wrapper := PanelContainer.new()
	wrapper.custom_minimum_size = SCALED_SIZE
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
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
	var click_handler := func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if is_pool:
					_on_pool_card_clicked(card_node)
				else:
					_on_deck_card_clicked(card_node)
			elif event.button_index == MOUSE_BUTTON_RIGHT and not is_pool:
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
				if count >= max_copies:
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
				move_btn.text = "→Main"
				move_btn.pressed.connect(_move_monster_to_main.bind(card_id))
			elif in_monster:
				move_btn.text = "→Main"
				move_btn.pressed.connect(_move_monster_to_main.bind(card_id))
			else:
				move_btn.text = "→Mon"
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
		_preview_card.rotation = -PI / 2.0
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
	_invalid_cards = DeckValidator.get_invalid_cards(_monster_entries, _main_entries)
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
	text += "[b]Monster Deck:[/b] %s%d / 4[/color]\n" % [mc, monster_count]
	text += "[b]Main Deck:[/b] %s%d / 50[/color]\n" % [mnc, main_count]
	text += "[b]Step-2 Cards:[/b] %s%d / 10[/color]" % [sc, step2_count]
	deck_stats_label.clear()
	deck_stats_label.append_text(text)

	_update_validation()


func _update_validation() -> void:
	validation_label.clear()
	var errors := DeckValidator.validate(_monster_entries, _main_entries)
	var warnings := DeckValidator.warnings(_monster_entries, _main_entries)

	if not errors.is_empty():
		validation_label.append_text("[color=red][b]Errors[/b][/color]\n")
		for err in errors:
			validation_label.append_text("[color=red]- %s[/color]\n" % err)
	if not warnings.is_empty():
		validation_label.append_text("[color=yellow][b]Warnings[/b][/color]\n")
		for warn in warnings:
			validation_label.append_text("[color=yellow]- %s[/color]\n" % warn)


# ============================================================
# Deck Tab Switching
# ============================================================

func _on_monster_tab_pressed() -> void:
	_showing_monster_tab = true
	_refresh_deck_display()


func _on_main_tab_pressed() -> void:
	_showing_monster_tab = false
	_refresh_deck_display()


# ============================================================
# Filter Handlers
# ============================================================

func _on_search_changed(new_text: String) -> void:
	_search_text = new_text.strip_edges().to_lower()
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
	var step := index + 1  # 0 → step 1, 1 → step 2
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


# ============================================================
# Save / Load / Delete
# ============================================================

func _on_save_pressed() -> void:
	var deck_name := deck_name_edit.text.strip_edges()
	if deck_name.is_empty():
		deck_name_edit.grab_focus()
		return
	DecklistManager.save_decklist(deck_name, _monster_entries, _main_entries)
	_current_deck_name = deck_name
	_has_unsaved_changes = false
	_refresh_deck_list()
	# Select saved deck in list
	for i in range(deck_list.item_count):
		if deck_list.get_item_text(i) == deck_name:
			deck_list.select(i)
			break


func _on_load_pressed() -> void:
	var selected := deck_list.get_selected_items()
	if selected.is_empty():
		return
	var deck_name: String = deck_list.get_item_text(selected[0])
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


func _on_deck_list_selected(index: int) -> void:
	deck_name_edit.text = deck_list.get_item_text(index)


func _on_delete_pressed() -> void:
	var selected := deck_list.get_selected_items()
	if selected.is_empty():
		return
	var deck_name: String = deck_list.get_item_text(selected[0])
	delete_dialog.dialog_text = "Delete \"%s\"?" % deck_name
	delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	var selected := deck_list.get_selected_items()
	if selected.is_empty():
		return
	var deck_name: String = deck_list.get_item_text(selected[0])
	DecklistManager.delete_decklist(deck_name)
	_refresh_deck_list()


func _refresh_deck_list() -> void:
	deck_list.clear()
	var names := DecklistManager.get_all_decklists()
	for deck_name in names:
		deck_list.add_item(deck_name)


# ============================================================
# Clipboard
# ============================================================

func _on_import_pressed() -> void:
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


func _on_export_pressed() -> void:
	var text := "[monster deck]\n"
	for entry in _monster_entries:
		text += "%d %s\n" % [entry["quantity"], entry["card_number"]]
	text += "\n[main deck]\n"
	for entry in _main_entries:
		text += "%d %s\n" % [entry["quantity"], entry["card_number"]]
	DisplayServer.clipboard_set(text)
	# Brief feedback
	export_button.text = "Copied!"
	get_tree().create_timer(1.5).timeout.connect(func(): export_button.text = "Export to Clipboard")


# ============================================================
# Navigation
# ============================================================

func _on_back_pressed() -> void:
	if _has_unsaved_changes:
		_pending_action = _go_to_menu
		unsaved_dialog.popup_centered()
		return
	_go_to_menu()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


func _on_unsaved_confirmed() -> void:
	if _pending_action.is_valid():
		_pending_action.call()
		_pending_action = Callable()
