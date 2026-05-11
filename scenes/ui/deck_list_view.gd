class_name DeckListView
extends VBoxContainer
## Reusable deck list with fuzzy search, thumbnails, and collapsible folders.
## Used by the Deck Builder (manage mode) and DeckSelect (compact mode).

signal deck_selected(deck_name: String)   ## Single click / tap.
signal deck_activated(deck_name: String)  ## Double-click / Enter — used by builder for Load.

const STATE_PATH := "user://deck_list_state.cfg"
const ROOT_KEY := "(Root)"
const ROW_INDENT := 18

## When true, hides the Move… button (DeckSelect pre-game picker).
@export var compact: bool = false
## When false, hides the Expand button (used for the inner list inside the expanded overlay).
@export var allow_expand: bool = true
## Optional header label shown above the search bar.
@export var header_text: String = ""
## Optional persist key — when set, last-selected deck is remembered across scenes.
@export var persist_key: String = ""

var current_selection: String = "":
	get:
		return _selected_deck
	set(value):
		select_deck(value)

var _selected_deck: String = ""
var _search_text: String = ""
var _collapsed_folders: Dictionary = {}
var _texture_cache: Dictionary = {}
var _entries: Array[Dictionary] = []
var _folder_order: Array[String] = []
var _entry_filter: Callable = Callable()  # Optional programmatic filter — (deck_name) -> bool
var _compact_rows: bool = false

var _header_label: Label
var _search_edit: LineEdit
var _density_button: Button
var _expand_button: Button
var _move_button: Button
var _scroll: ScrollContainer
var _list_vbox: VBoxContainer
var _empty_label: Label
var _search_timer: Timer
var _row_buttons: Dictionary = {}  # deck_name → DeckRow
var _folder_headers: Dictionary = {}  # folder_path → Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.15
	_search_timer.timeout.connect(_apply_filter)
	add_child(_search_timer)

	_build_ui()
	_load_state()
	refresh()
	if not persist_key.is_empty():
		var last := _load_last_selected()
		if not last.is_empty():
			select_deck(last)


func _build_ui() -> void:
	_header_label = Label.new()
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 16)
	_header_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	_header_label.visible = not header_text.is_empty()
	if not header_text.is_empty():
		_header_label.text = tr(header_text)
	add_child(_header_label)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)
	add_child(top_row)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = tr("STR_DLV_SEARCH_PLACEHOLDER")
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_changed)
	top_row.add_child(_search_edit)

	_density_button = Button.new()
	_density_button.toggle_mode = true
	_density_button.focus_mode = Control.FOCUS_NONE
	_density_button.custom_minimum_size.x = 32
	_density_button.tooltip_text = tr("STR_DLV_TOGGLE_DENSITY")
	_density_button.text = "≡"
	_density_button.toggled.connect(_on_density_toggled)
	top_row.add_child(_density_button)

	_expand_button = Button.new()
	_expand_button.focus_mode = Control.FOCUS_NONE
	_expand_button.custom_minimum_size.x = 32
	_expand_button.tooltip_text = tr("STR_DLV_EXPAND")
	_expand_button.text = "⛶"
	_expand_button.visible = allow_expand
	_expand_button.pressed.connect(_on_expand_pressed)
	top_row.add_child(_expand_button)

	_move_button = Button.new()
	_move_button.text = tr("STR_DB_MOVE")
	_move_button.disabled = true
	_move_button.visible = not compact
	_move_button.pressed.connect(_on_move_pressed)
	top_row.add_child(_move_button)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 20
	_scroll.custom_minimum_size.y = 180
	add_child(_scroll)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.04, 0.03, 0.6)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	_scroll.add_child(panel)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 2)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_list_vbox)

	_empty_label = Label.new()
	_empty_label.text = tr("STR_DLV_NO_DECKS")
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.5, 1))
	_empty_label.visible = false
	add_child(_empty_label)


# --- Public API ---

func refresh() -> void:
	_entries = DecklistManager.get_all_deck_entries()
	_compute_folder_order()
	_rebuild()
	_update_move_button()


func select_deck(deck_name: String) -> void:
	if _selected_deck == deck_name:
		return
	_selected_deck = deck_name
	for n in _row_buttons:
		var row: DeckRow = _row_buttons[n]
		row.set_selected(n == deck_name)
	_update_move_button()
	if not persist_key.is_empty() and not deck_name.is_empty():
		_save_last_selected(deck_name)


func get_selected_deck() -> String:
	return _selected_deck


func clear_selection() -> void:
	_selected_deck = ""
	for n in _row_buttons:
		(_row_buttons[n] as DeckRow).set_selected(false)
	_update_move_button()


func set_header(text: String) -> void:
	header_text = text
	if _header_label != null:
		_header_label.text = tr(text)
		_header_label.visible = not text.is_empty()


func set_header_visible(value: bool) -> void:
	if _header_label != null:
		_header_label.visible = value


func set_filter(callable: Callable) -> void:
	## Programmatic filter applied after the fuzzy search.
	## Pass an empty Callable to clear.
	_entry_filter = callable
	_rebuild()


func set_disabled(value: bool) -> void:
	## Disables interaction (used by lobbies during host/connect transitions).
	if _search_edit != null:
		_search_edit.editable = not value
	if _move_button != null:
		_move_button.disabled = value or _selected_deck.is_empty()
	for n in _row_buttons:
		var row: DeckRow = _row_buttons[n]
		row.disabled = value


# --- Internals ---

func _compute_folder_order() -> void:
	_folder_order.clear()
	var seen := {"": true}
	_folder_order.append("")
	for entry in _entries:
		var f: String = entry["folder"]
		if not seen.has(f):
			seen[f] = true
			_folder_order.append(f)
	# Sort folders: root first, then alphabetical.
	var rest: Array[String] = []
	for i in range(1, _folder_order.size()):
		rest.append(_folder_order[i])
	rest.sort()
	_folder_order.clear()
	_folder_order.append("")
	for f in rest:
		_folder_order.append(f)


func _rebuild() -> void:
	if _list_vbox == null:
		return  # Not built yet — refresh() will be called again from _ready.
	for child in _list_vbox.get_children():
		_list_vbox.remove_child(child)
		child.queue_free()
	_row_buttons.clear()
	_folder_headers.clear()

	var any_visible := false
	for folder in _folder_order:
		var folder_entries := _entries_in_folder(folder)
		var visible_entries := _filter_entries(folder_entries)
		if visible_entries.is_empty():
			continue
		var collapsed: bool = _collapsed_folders.get(folder, false)
		if not _search_text.is_empty():
			collapsed = false
		_add_folder_header(folder, visible_entries.size(), collapsed)
		if not collapsed:
			for entry in visible_entries:
				_add_deck_row(entry)
		any_visible = true

	_empty_label.visible = not any_visible
	if not _selected_deck.is_empty() and _row_buttons.has(_selected_deck):
		(_row_buttons[_selected_deck] as DeckRow).set_selected(true)


func _entries_in_folder(folder: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _entries:
		if entry["folder"] == folder:
			out.append(entry)
	return out


func _filter_entries(entries: Array[Dictionary]) -> Array[Dictionary]:
	var pre_filtered: Array[Dictionary] = []
	for entry in entries:
		if _entry_filter.is_valid() and not _entry_filter.call(entry["name"]):
			continue
		pre_filtered.append(entry)
	if _search_text.is_empty():
		var sorted: Array[Dictionary] = pre_filtered.duplicate()
		sorted.sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
		return sorted
	var scored: Array = []
	for entry in pre_filtered:
		var s := FuzzyMatch.score(_search_text, entry["name"])
		if s >= 0:
			scored.append({"entry": entry, "score": s})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	var out: Array[Dictionary] = []
	for item in scored:
		out.append(item["entry"])
	return out


func _add_folder_header(folder: String, count: int, collapsed: bool) -> void:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_pressed = not collapsed
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(0.85, 0.55, 0.35, 1))
	var arrow := "▾" if not collapsed else "▸"
	var label := ROOT_KEY if folder.is_empty() else folder
	if collapsed:
		btn.text = "%s %s (%d)" % [arrow, label, count]
	else:
		btn.text = "%s %s" % [arrow, label]
	btn.toggled.connect(_on_folder_toggled.bind(folder))
	_list_vbox.add_child(btn)
	_folder_headers[folder] = btn


func _add_deck_row(entry: Dictionary) -> void:
	var row := DeckRow.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("hseparation", ROW_INDENT)
	var thumb_id := DecklistManager.get_decklist_thumbnail_card_id(entry["name"])
	var tex := DeckRow.resolve_thumbnail_texture(thumb_id, _texture_cache)
	row.set_data(entry["name"], entry["folder"], tex)
	row.selected.connect(_on_row_selected)
	row.activated.connect(_on_row_activated)
	_list_vbox.add_child(row)
	row.set_compact_mode(_compact_rows)
	_row_buttons[entry["name"]] = row
	if entry["name"] == _selected_deck:
		row.set_selected(true)


func _on_folder_toggled(pressed: bool, folder: String) -> void:
	_collapsed_folders[folder] = not pressed
	_save_state()
	_rebuild()


func _on_density_toggled(pressed: bool) -> void:
	_compact_rows = pressed
	for n in _row_buttons:
		(_row_buttons[n] as DeckRow).set_compact_mode(_compact_rows)
	_save_state()


func _on_expand_pressed() -> void:
	SfxManager.play("ui_click")
	_open_expanded_overlay()


func _open_expanded_overlay() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	get_tree().root.add_child(overlay)
	# Click outside the panel dismisses.
	overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			overlay.queue_free()
	)

	var panel := PanelContainer.new()
	var viewport_size := get_viewport().get_visible_rect().size
	var w := minf(viewport_size.x * 0.7, 800.0)
	var h := minf(viewport_size.y * 0.9, 1100.0)
	panel.custom_minimum_size = Vector2(w, h)
	panel.size = Vector2(w, h)
	panel.position = (viewport_size - Vector2(w, h)) * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.06, 0.04, 0.98)
	style.border_color = Color(0.9, 0.3, 0.1, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	col.add_child(header_row)

	var title := Label.new()
	title.text = tr("STR_DLV_EXPANDED_TITLE")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(overlay.queue_free)
	header_row.add_child(close_btn)

	var inner := DeckListView.new()
	inner.compact = compact
	inner.allow_expand = false
	inner.persist_key = persist_key
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _entry_filter.is_valid():
		inner.set_filter(_entry_filter)
	col.add_child(inner)
	if not _selected_deck.is_empty():
		inner.select_deck(_selected_deck)

	# Single-click selection mirrors back to parent + closes.
	inner.deck_selected.connect(func(deck_name):
		select_deck(deck_name)
		deck_selected.emit(deck_name)
	)
	inner.deck_activated.connect(func(deck_name):
		select_deck(deck_name)
		deck_activated.emit(deck_name)
		overlay.queue_free()
	)


func _on_row_selected(deck_name: String) -> void:
	SfxManager.play("ui_click")
	select_deck(deck_name)
	deck_selected.emit(deck_name)


func _on_row_activated(deck_name: String) -> void:
	select_deck(deck_name)
	deck_activated.emit(deck_name)


func _on_search_changed(text: String) -> void:
	_search_text = text.strip_edges()
	_search_timer.stop()
	_search_timer.start()


func _apply_filter() -> void:
	_rebuild()


func _on_move_pressed() -> void:
	if _selected_deck.is_empty():
		return
	SfxManager.play("ui_click")
	var picker := preload("res://scenes/ui/folder_picker_dialog.gd").new()
	add_child(picker)
	var current_folder := DecklistManager.get_deck_folder(_selected_deck)
	picker.show_for(_selected_deck, current_folder)
	picker.folder_chosen.connect(_on_folder_chosen)


func _on_folder_chosen(target_folder: String) -> void:
	if _selected_deck.is_empty():
		return
	var ok := DecklistManager.move_decklist(_selected_deck, target_folder)
	if not ok:
		# Surface a brief error via the empty label; not critical to add a dialog here.
		_empty_label.text = tr("STR_DLV_FOLDER_EXISTS")
		_empty_label.visible = true
		await get_tree().create_timer(2.0).timeout
		_empty_label.text = tr("STR_DLV_NO_DECKS")
		return
	var remember := _selected_deck
	refresh()
	select_deck(remember)


func _update_move_button() -> void:
	if _move_button == null:
		return
	_move_button.disabled = _selected_deck.is_empty()


# --- State persistence ---

func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(STATE_PATH) != OK:
		return
	if cfg.has_section("collapsed"):
		for key in cfg.get_section_keys("collapsed"):
			_collapsed_folders[key] = cfg.get_value("collapsed", key, false)
	_compact_rows = cfg.get_value("view", "compact_rows", false)
	if _density_button != null:
		_density_button.set_pressed_no_signal(_compact_rows)


func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	if cfg.has_section("collapsed"):
		cfg.erase_section("collapsed")
	for key in _collapsed_folders:
		cfg.set_value("collapsed", key, _collapsed_folders[key])
	cfg.set_value("view", "compact_rows", _compact_rows)
	cfg.save(STATE_PATH)


func _save_last_selected(deck_name: String) -> void:
	if persist_key.is_empty():
		return
	var cfg := ConfigFile.new()
	var path := "user://deck_select.cfg"
	cfg.load(path)
	cfg.set_value("deck_select", persist_key, deck_name)
	cfg.save(path)


func _load_last_selected() -> String:
	if persist_key.is_empty():
		return ""
	var cfg := ConfigFile.new()
	if cfg.load("user://deck_select.cfg") != OK:
		return ""
	return cfg.get_value("deck_select", persist_key, "")
