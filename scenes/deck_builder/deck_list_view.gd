class_name DeckListView
extends VBoxContainer
## Reusable deck list with fuzzy search, thumbnails, and collapsible folders.
## Used by the Deck Builder (manage mode) and DeckSelect (compact mode).

signal deck_selected(deck_name: String)   ## Single click / tap.
signal deck_activated(deck_name: String)  ## Double-click / Enter — used by builder for Load.

const STATE_PATH := "user://deck_list_state.cfg"
const ROW_INDENT := 18

## When true, render as a picker button that opens the full list in a modal.
## When false, render the full inline list with search + folders.
@export var compact: bool = false
## When false, hides the Move… button (used inside the expand modal + picker mode).
@export var allow_move: bool = true
## When false, hides the Expand button (used for the inner list inside the expanded overlay).
@export var allow_expand: bool = true
## When true, each row displays a ⋯ menu (Move to folder…, etc.). Used by the expand overlay.
@export var show_row_actions: bool = false
## When true, render a Format dropdown next to the search bar. The dropdown
## greys out decks that aren't legal in the chosen format; selection persists
## via `GameSettings.deck_list_format`.
@export var show_format_filter: bool = false
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
var _active_overlay: Control = null
var _format_id: String = ""              # GameModeValidator mode id; "" = Any
var _eligibility: Dictionary = {}        # deck_name → bool (populated when _format_id set)

var _header_label: Label
var _search_edit: LineEdit
var _format_option: OptionButton
var _density_button: Button
var _expand_button: Button
var _move_button: Button
var _scroll: ScrollContainer
var _list_vbox: VBoxContainer
var _empty_label: Label
var _search_timer: Timer
var _row_buttons: Dictionary = {}  # deck_name → DeckRow
var _folder_headers: Dictionary = {}  # folder_path → Button

# Picker-mode widgets (when compact=true)
var _picker_button: Button
var _picker_thumb: TextureRect
var _picker_placeholder: Label
var _picker_label: Label
var _picker_folder_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if compact:
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
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


func _unhandled_input(event: InputEvent) -> void:
	if _active_overlay == null:
		return
	if event.is_action_pressed("ui_cancel"):
		_active_overlay.queue_free()
		_active_overlay = null
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_header_label = Label.new()
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 16)
	_header_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	_header_label.visible = not header_text.is_empty()
	if not header_text.is_empty():
		_header_label.text = tr(header_text)
	add_child(_header_label)

	if compact:
		_build_picker_ui()
	else:
		_build_full_ui()


func _build_picker_ui() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)

	_picker_button = Button.new()
	_picker_button.custom_minimum_size.y = 60
	_picker_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_button.clip_text = true
	_picker_button.text = ""
	_picker_button.pressed.connect(_on_picker_pressed)
	row.add_child(_picker_button)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 8
	hbox.offset_right = -8
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker_button.add_child(hbox)

	var thumb_holder := Control.new()
	thumb_holder.custom_minimum_size = Vector2(DeckRow.THUMB_SIZE.x, DeckRow.THUMB_SIZE.y)
	thumb_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_holder.clip_contents = true
	hbox.add_child(thumb_holder)

	_picker_placeholder = Label.new()
	_picker_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_picker_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_picker_placeholder.add_theme_font_size_override("font_size", 18)
	_picker_placeholder.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3, 1))
	_picker_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ph_style := StyleBoxFlat.new()
	ph_style.bg_color = Color(0.18, 0.10, 0.07, 1)
	ph_style.set_corner_radius_all(3)
	var ph_panel := PanelContainer.new()
	ph_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ph_panel.add_theme_stylebox_override("panel", ph_style)
	ph_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph_panel.add_child(_picker_placeholder)
	thumb_holder.add_child(ph_panel)

	_picker_thumb = TextureRect.new()
	_picker_thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picker_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_picker_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker_thumb.visible = false
	thumb_holder.add_child(_picker_thumb)

	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.add_theme_constant_override("separation", 0)
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_col)

	_picker_label = Label.new()
	_picker_label.clip_text = true
	_picker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_picker_label.add_theme_font_size_override("font_size", 16)
	_picker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_picker_label)

	_picker_folder_label = Label.new()
	_picker_folder_label.clip_text = true
	_picker_folder_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_picker_folder_label.add_theme_font_size_override("font_size", 11)
	_picker_folder_label.add_theme_color_override("font_color", Color(0.65, 0.5, 0.35, 1))
	_picker_folder_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_picker_folder_label)

	var chevron := Label.new()
	chevron.text = "▾"
	chevron.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3, 1))
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(chevron)

	# Move… button (deck builder only). Expand is unnecessary in compact mode —
	# the picker button itself opens the full list modal.
	if allow_move:
		_move_button = Button.new()
		_move_button.text = tr("STR_DB_MOVE")
		_move_button.disabled = true
		_move_button.custom_minimum_size.y = 60
		_move_button.pressed.connect(_on_move_pressed)
		row.add_child(_move_button)

	_update_picker_button()


func _build_full_ui() -> void:
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)
	add_child(top_row)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = tr("STR_DLV_SEARCH_PLACEHOLDER")
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_changed)
	top_row.add_child(_search_edit)

	if show_format_filter:
		_format_option = OptionButton.new()
		GamepadHelper.make_pad_focusable(_format_option)
		_format_option.tooltip_text = tr("STR_DLV_FORMAT_TOOLTIP")
		_format_option.add_item(tr("STR_MENU_FORMAT_ANY"), 0)
		_format_option.set_item_metadata(0, "")
		_format_id = GameSettings.deck_list_format
		for i in range(GameModeValidator.MODES.size()):
			var mode: Dictionary = GameModeValidator.MODES[i]
			var idx := _format_option.item_count
			_format_option.add_item(tr(mode["label"]), idx)
			_format_option.set_item_metadata(idx, mode["id"])
			if String(mode["id"]) == _format_id:
				_format_option.select(idx)
		_format_option.item_selected.connect(_on_format_selected)
		top_row.add_child(_format_option)

	_density_button = Button.new()
	_density_button.toggle_mode = true
	GamepadHelper.make_pad_focusable(_density_button)
	_density_button.custom_minimum_size.x = 32
	_density_button.tooltip_text = tr("STR_DLV_TOGGLE_DENSITY")
	_density_button.text = "≡"
	_density_button.toggled.connect(_on_density_toggled)
	top_row.add_child(_density_button)

	_expand_button = Button.new()
	GamepadHelper.make_pad_focusable(_expand_button)
	_expand_button.custom_minimum_size.x = 32
	_expand_button.tooltip_text = tr("STR_DLV_EXPAND")
	_expand_button.text = "⛶"
	_expand_button.visible = allow_expand
	_expand_button.pressed.connect(_on_expand_pressed)
	top_row.add_child(_expand_button)

	_move_button = Button.new()
	_move_button.text = tr("STR_DB_MOVE")
	_move_button.disabled = true
	_move_button.visible = allow_move
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
	_rebuild_eligibility()
	_rebuild()
	_update_move_button()
	_update_picker_button()


func select_deck(deck_name: String) -> void:
	if _selected_deck == deck_name:
		return
	_selected_deck = deck_name
	for n in _row_buttons:
		var row: DeckRow = _row_buttons[n]
		row.set_selected(n == deck_name)
	_update_move_button()
	_update_picker_button()
	if not persist_key.is_empty() and not deck_name.is_empty():
		_save_last_selected(deck_name)


func get_selected_deck() -> String:
	return _selected_deck


func clear_selection() -> void:
	_selected_deck = ""
	for n in _row_buttons:
		(_row_buttons[n] as DeckRow).set_selected(false)
	_update_move_button()
	_update_picker_button()


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
	if _picker_button != null:
		_picker_button.disabled = value
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
	if compact:
		return  # Picker mode has no inline list to rebuild.
	if _list_vbox == null:
		return  # Not built yet — refresh() will be called again from _ready.
	for child in _list_vbox.get_children():
		_list_vbox.remove_child(child)
		child.queue_free()
	_row_buttons.clear()
	_folder_headers.clear()

	var any_visible := false
	# Skip the root header entirely when there are no subfolders to group against —
	# a flat list shouldn't display an "Uncategorized" header.
	var has_subfolders := _folder_order.size() > 1
	for folder in _folder_order:
		var folder_entries := _entries_in_folder(folder)
		var visible_entries := _filter_entries(folder_entries)
		if visible_entries.is_empty():
			continue
		var should_render_header := folder != "" or has_subfolders
		var collapsed: bool = _collapsed_folders.get(folder, false)
		# No header → no way to expand back, so force rows visible.
		if not should_render_header:
			collapsed = false
		if should_render_header:
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
	GamepadHelper.make_pad_focusable(btn)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(0.85, 0.55, 0.35, 1))
	var arrow := "▾" if not collapsed else "▸"
	var label := tr("STR_DLV_ROOT") if folder.is_empty() else folder
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
	row.action_requested.connect(_on_row_action_requested)
	_list_vbox.add_child(row)
	row.set_compact_mode(_compact_rows)
	row.set_actions_visible(show_row_actions)
	row.set_dimmed(not _is_deck_eligible(entry["name"]))
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


func _on_format_selected(_idx: int) -> void:
	SfxManager.play("ui_click")
	if _format_option == null:
		return
	_format_id = String(_format_option.get_selected_metadata())
	GameSettings.deck_list_format = _format_id
	GameSettings.save()
	_rebuild_eligibility()
	_apply_eligibility_to_rows()


func _rebuild_eligibility() -> void:
	_eligibility.clear()
	if _format_id.is_empty():
		return
	for entry in _entries:
		var dn: String = entry["name"]
		_eligibility[dn] = DecklistManager.is_decklist_valid_for_mode(dn, _format_id)


func _is_deck_eligible(deck_name: String) -> bool:
	if _format_id.is_empty():
		return true
	return bool(_eligibility.get(deck_name, true))


func _apply_eligibility_to_rows() -> void:
	for dn in _row_buttons:
		(_row_buttons[dn] as DeckRow).set_dimmed(not _is_deck_eligible(dn))


func _on_expand_pressed() -> void:
	SfxManager.play("ui_click")
	_open_expanded_overlay()


func _on_picker_pressed() -> void:
	SfxManager.play("ui_click")
	_open_expanded_overlay()


func _update_picker_button() -> void:
	if _picker_button == null:
		return
	if _selected_deck.is_empty():
		_picker_label.text = tr("STR_DLV_PICKER_EMPTY")
		_picker_folder_label.text = ""
		_picker_folder_label.visible = false
		_picker_thumb.visible = false
		_picker_thumb.texture = null
		_picker_placeholder.text = "?"
		return
	_picker_label.text = _selected_deck
	var folder := DecklistManager.get_deck_folder(_selected_deck)
	if folder.is_empty():
		_picker_folder_label.text = tr("STR_DLV_ROOT")
	else:
		_picker_folder_label.text = folder
	_picker_folder_label.visible = true
	var thumb_id := DecklistManager.get_decklist_thumbnail_card_id(_selected_deck)
	var tex := DeckRow.resolve_thumbnail_texture(thumb_id, _texture_cache)
	if tex != null:
		_picker_thumb.texture = tex
		_picker_thumb.visible = true
		_picker_placeholder.text = ""
	else:
		_picker_thumb.texture = null
		_picker_thumb.visible = false
		_picker_placeholder.text = _selected_deck.substr(0, 1).to_upper()


func _open_expanded_overlay() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	get_tree().root.add_child(overlay)
	_active_overlay = overlay
	overlay.tree_exiting.connect(func(): if _active_overlay == overlay: _active_overlay = null)
	# Click outside the panel dismisses. Only react to real click buttons —
	# mouse-wheel events are also InputEventMouseButton (pressed == true) and
	# bubble up here when the ScrollContainer can't scroll any further, which
	# would otherwise close the list when scrolling past the top/bottom.
	overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and \
				event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
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
	GamepadHelper.make_pad_focusable(close_btn)
	close_btn.pressed.connect(overlay.queue_free)
	header_row.add_child(close_btn)

	var inner := DeckListView.new()
	inner.compact = false
	inner.allow_move = false
	inner.allow_expand = false
	inner.show_row_actions = true
	inner.show_format_filter = true
	inner.persist_key = persist_key
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _entry_filter.is_valid():
		inner.set_filter(_entry_filter)
	col.add_child(inner)
	if not _selected_deck.is_empty():
		inner.select_deck(_selected_deck)

	# Picker-mode (lobby-style): single click selects and closes.
	# Full-mode (DeckBuilder): single click selects, double-click activates and closes.
	var close_on_select := compact
	inner.deck_selected.connect(func(deck_name):
		select_deck(deck_name)
		deck_selected.emit(deck_name)
		if close_on_select:
			overlay.queue_free()
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
	_open_folder_picker(_selected_deck)


func _on_row_action_requested(deck_name: String, anchor: Vector2) -> void:
	SfxManager.play("ui_click")
	var menu := PopupMenu.new()
	menu.add_item(tr("STR_DLV_MOVE_TO_FOLDER"), 0)
	add_child(menu)
	menu.position = Vector2i(anchor)
	menu.popup()
	menu.id_pressed.connect(func(id):
		if id == 0:
			_open_folder_picker(deck_name)
		menu.queue_free()
	)
	menu.popup_hide.connect(menu.queue_free)


func _open_folder_picker(deck_name: String) -> void:
	var picker := preload("res://scenes/deck_builder/folder_picker_dialog.gd").new()
	add_child(picker)
	var current_folder := DecklistManager.get_deck_folder(deck_name)
	picker.show_for(deck_name, current_folder)
	picker.folder_chosen.connect(_on_folder_chosen.bind(deck_name))


func _on_folder_chosen(target_folder: String, deck_name: String) -> void:
	if deck_name.is_empty():
		return
	var ok := DecklistManager.move_decklist(deck_name, target_folder)
	if not ok:
		_empty_label.text = tr("STR_DLV_FOLDER_EXISTS")
		_empty_label.visible = true
		await get_tree().create_timer(2.0).timeout
		_empty_label.text = tr("STR_DLV_NO_DECKS")
		return
	refresh()
	select_deck(deck_name)


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
