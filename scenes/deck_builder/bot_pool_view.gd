class_name BotPoolView
extends VBoxContainer
## Bot deck-pool editor with folder grouping + fuzzy search.
##
## Mirrors the look-and-feel of DeckListView: folder headers with arrows,
## collapse-state persisted in user://deck_list_state.cfg (shared section
## "collapsed"). Each deck row is a checkbox + small thumb + name + [−][N][+]
## stepper. Folder header rows have the same stepper plus a checkbox to
## include the whole folder. When a folder is enabled, the deck rows inside
## it visually disable (folder takes over per shipped semantics).

## Fired after _rebuild replaces the rows — the owner re-wires its pad focus
## mesh over pad_row_bands() (the old rows, and their neighbors, are freed).
signal rows_rebuilt

const STATE_PATH := "user://deck_list_state.cfg"
const ROW_INDENT := 18
const WEIGHT_MIN := 1
const WEIGHT_MAX := 100
const ROW_HEIGHT_DECK := 48
const ROW_HEIGHT_FOLDER := 40

# State
var _deck_weights: Dictionary = {}  # deck_name → int
var _folder_weights: Dictionary = {}  # folder_path → int (0 = disabled)
var _collapsed_folders: Dictionary = {}
var _texture_cache: Dictionary = {}
var _entries: Array[Dictionary] = []
var _folder_order: Array[String] = []
var _search_text: String = ""
var _random_enabled: bool = true
var _setup_called: bool = false
var _format_id: String = ""               # GameModeValidator mode id; "" = Any
var _eligibility: Dictionary = {}         # deck_name → bool (populated when _format_id set)

# UI references
var _search_edit: LineEdit
var _select_all_btn: Button
var _reset_weights_btn: Button
var _list_vbox: VBoxContainer
var _search_timer: Timer
var _deck_rows: Dictionary = {}  # deck_name → {check, dec, inp, inc, thumb_holder, container}
var _folder_rows: Dictionary = {}  # folder_path → {check, dec, inp, inc, arrow_btn, container}
var _pad_row_bands: Array[Dictionary] = []  # ordered {"row": Array[Control]} per visible row


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
	if _setup_called:
		_populate()
		_apply_random_enabled_to_all()


func _build_ui() -> void:
	# Top strip: search bar + Reset Weights + Select All
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	add_child(top_row)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = tr("STR_MENU_BOT_POOL_SEARCH")
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_changed)
	top_row.add_child(_search_edit)

	_reset_weights_btn = Button.new()
	_reset_weights_btn.text = tr("STR_MENU_DECK_RESET_WEIGHTS")
	_reset_weights_btn.add_theme_font_size_override("font_size", 14)
	_reset_weights_btn.pressed.connect(_on_reset_weights_pressed)
	top_row.add_child(_reset_weights_btn)

	_select_all_btn = Button.new()
	_select_all_btn.add_theme_font_size_override("font_size", 14)
	_select_all_btn.pressed.connect(_on_select_all_pressed)
	top_row.add_child(_select_all_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 20
	scroll.custom_minimum_size.y = 260
	scroll.follow_focus = true  # dpad walks the rows; the list must scroll along
	add_child(scroll)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.04, 0.03, 0.6)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	scroll.add_child(panel)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 2)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_list_vbox)


# --- Public API ---

func setup(deck_weights: Dictionary, folder_weights: Dictionary) -> void:
	_deck_weights = deck_weights.duplicate()
	_folder_weights = folder_weights.duplicate()
	_setup_called = true
	if _list_vbox != null:
		_populate()


func _populate() -> void:
	_entries = DecklistManager.get_all_deck_entries()
	_compute_folder_order()
	_rebuild_eligibility()
	_rebuild()
	_refresh_select_all_label()


func get_deck_weights() -> Dictionary:
	_commit_all_pending_edits()
	return _deck_weights.duplicate()


func get_folder_weights() -> Dictionary:
	_commit_all_pending_edits()
	# Strip disabled (weight=0) entries — they're not meaningful to persist.
	var out: Dictionary = {}
	for fp in _folder_weights:
		var w := int(_folder_weights[fp])
		if w > 0:
			out[fp] = w
	return out


func set_random_enabled(value: bool) -> void:
	_random_enabled = value
	_apply_random_enabled_to_all()


func set_format(mode_id: String) -> void:
	## Filter the visible pool by format eligibility. Empty = "Any" (no filter).
	## Storage (deck/folder weights) is left untouched — re-selecting "Any"
	## restores the previous view with no data loss.
	_format_id = mode_id
	_rebuild_eligibility()
	_apply_folder_takeover_to_all()
	_refresh_select_all_label()


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
		return
	for child in _list_vbox.get_children():
		_list_vbox.remove_child(child)
		child.queue_free()
	_deck_rows.clear()
	_folder_rows.clear()
	_pad_row_bands.clear()

	var has_subfolders := _folder_order.size() > 1
	for folder in _folder_order:
		var folder_entries := _entries_in_folder(folder)
		var visible_entries := _filter_entries(folder_entries, folder)
		if visible_entries.is_empty() and not _folder_name_matches(folder):
			continue
		var should_render_header := folder != "" or has_subfolders
		var collapsed: bool = _collapsed_folders.get(folder, false)
		if not should_render_header:
			collapsed = false
		if should_render_header:
			_add_folder_header(folder, collapsed)
		if not collapsed:
			for entry in visible_entries:
				_add_deck_row(entry)

	_apply_folder_takeover_to_all()
	_apply_random_enabled_to_all()
	rows_rebuilt.emit()


## The top strip's pad-focusable controls, left to right.
func pad_header_controls() -> Array[Control]:
	var out: Array[Control] = [_search_edit, _reset_weights_btn, _select_all_btn]
	return out


## Ordered {"row": Array[Control]} bands for the currently visible rows —
## feed them to OverlayGridUtil.wire_band_stack (re-wire on rows_rebuilt).
func pad_row_bands() -> Array[Dictionary]:
	return _pad_row_bands.duplicate()


func _entries_in_folder(folder: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _entries:
		if entry["folder"] == folder:
			out.append(entry)
	return out


func _filter_entries(entries: Array[Dictionary], folder: String) -> Array[Dictionary]:
	if _search_text.is_empty():
		var sorted: Array[Dictionary] = entries.duplicate()
		sorted.sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
		return sorted
	# If the folder name itself matches, surface all its decks regardless of name match.
	if not folder.is_empty() and FuzzyMatch.score(_search_text, folder) >= 0:
		var sorted2: Array[Dictionary] = entries.duplicate()
		sorted2.sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
		return sorted2
	var scored: Array = []
	for entry in entries:
		var s := FuzzyMatch.score(_search_text, entry["name"])
		if s >= 0:
			scored.append({"entry": entry, "score": s})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	var out: Array[Dictionary] = []
	for item in scored:
		out.append(item["entry"])
	return out


func _folder_name_matches(folder: String) -> bool:
	if _search_text.is_empty():
		return true
	if folder.is_empty():
		return false
	return FuzzyMatch.score(_search_text, folder) >= 0


func _add_folder_header(folder: String, collapsed: bool) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT_FOLDER
	row.add_theme_constant_override("separation", 6)
	_list_vbox.add_child(row)

	var arrow_btn := Button.new()
	arrow_btn.flat = true
	GamepadHelper.make_pad_focusable(arrow_btn)
	arrow_btn.custom_minimum_size = Vector2(24, ROW_HEIGHT_FOLDER)
	arrow_btn.add_theme_font_size_override("font_size", 14)
	arrow_btn.text = "▾" if not collapsed else "▸"
	arrow_btn.pressed.connect(_on_folder_arrow_pressed.bind(folder))
	row.add_child(arrow_btn)

	var check := CheckBox.new()
	check.text = tr("STR_DLV_ROOT") if folder.is_empty() else folder
	check.tooltip_text = tr("STR_MENU_BOT_FOLDER_TIP")
	check.add_theme_font_size_override("font_size", 14)
	check.add_theme_color_override("font_color", Color(0.85, 0.55, 0.35, 1))
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.clip_text = true
	var saved_w := int(_folder_weights.get(folder, 0))
	check.button_pressed = saved_w > 0
	check.toggled.connect(_on_folder_check_toggled.bind(folder))
	row.add_child(check)

	var count_label := Label.new()
	count_label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.35, 1))
	count_label.add_theme_font_size_override("font_size", 13)
	row.add_child(count_label)

	var pct_label := Label.new()
	pct_label.custom_minimum_size.x = 64
	pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct_label.add_theme_font_size_override("font_size", 12)
	pct_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7, 1))
	row.add_child(pct_label)

	var stepper_widgets := _build_stepper(maxi(saved_w, WEIGHT_MIN))
	row.add_child(stepper_widgets["container"])

	stepper_widgets["inp"].text_submitted.connect(func(_t): _persist_folder_weight(folder))
	stepper_widgets["inp"].focus_exited.connect(func(): _persist_folder_weight(folder))
	stepper_widgets["dec"].pressed.connect(func(): _persist_folder_weight(folder))
	stepper_widgets["inc"].pressed.connect(func(): _persist_folder_weight(folder))

	_folder_rows[folder] = {
		"check": check,
		"dec": stepper_widgets["dec"],
		"inp": stepper_widgets["inp"],
		"inc": stepper_widgets["inc"],
		"arrow_btn": arrow_btn,
		"container": row,
		"count_label": count_label,
		"pct_label": pct_label,
		"collapsed": collapsed,
	}
	_pad_row_bands.append({"row": [arrow_btn, check, stepper_widgets["dec"],
			stepper_widgets["inp"], stepper_widgets["inc"]] as Array[Control]})
	_refresh_folder_count(folder)


func _add_deck_row(entry: Dictionary) -> void:
	var deck_name: String = entry["name"]
	var folder: String = entry["folder"]

	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT_DECK
	row.add_theme_constant_override("separation", 6)
	_list_vbox.add_child(row)

	# Indent under folder header
	var spacer := Control.new()
	spacer.custom_minimum_size.x = ROW_INDENT
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# Thumbnail
	var thumb_holder := Control.new()
	thumb_holder.custom_minimum_size = Vector2(DeckRow.THUMB_SIZE.x, DeckRow.THUMB_SIZE.y)
	thumb_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb_holder.clip_contents = true
	row.add_child(thumb_holder)

	var thumb_id := DecklistManager.get_decklist_thumbnail_card_id(deck_name)
	var tex := DeckRow.resolve_thumbnail_texture(thumb_id, _texture_cache)
	if tex != null:
		var tr_node := TextureRect.new()
		tr_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr_node.texture = tex
		tr_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb_holder.add_child(tr_node)

	# Checkbox + name
	var check := CheckBox.new()
	check.text = deck_name
	check.tooltip_text = deck_name
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.clip_text = true
	var has_entry: bool = _deck_weights.has(deck_name)
	var saved_w: int = int(_deck_weights.get(deck_name, 1))
	check.button_pressed = (not has_entry) or saved_w > 0
	row.add_child(check)

	var pct_label := Label.new()
	pct_label.custom_minimum_size.x = 64
	pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct_label.add_theme_font_size_override("font_size", 12)
	pct_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7, 1))
	row.add_child(pct_label)

	# Stepper
	var stepper_widgets := _build_stepper(maxi(saved_w, WEIGHT_MIN))
	row.add_child(stepper_widgets["container"])

	check.toggled.connect(_on_deck_check_toggled.bind(deck_name))
	stepper_widgets["inp"].text_submitted.connect(func(_t): _persist_deck_weight(deck_name))
	stepper_widgets["inp"].focus_exited.connect(func(): _persist_deck_weight(deck_name))
	stepper_widgets["dec"].pressed.connect(func(): _persist_deck_weight(deck_name))
	stepper_widgets["inc"].pressed.connect(func(): _persist_deck_weight(deck_name))

	_deck_rows[deck_name] = {
		"check": check,
		"dec": stepper_widgets["dec"],
		"inp": stepper_widgets["inp"],
		"inc": stepper_widgets["inc"],
		"thumb_holder": thumb_holder,
		"container": row,
		"folder": folder,
		"pct_label": pct_label,
	}
	_pad_row_bands.append({"row": [check, stepper_widgets["dec"],
			stepper_widgets["inp"], stepper_widgets["inc"]] as Array[Control]})


func _build_stepper(initial: int) -> Dictionary:
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 2)

	var dec_btn := Button.new()
	dec_btn.text = "−"
	dec_btn.custom_minimum_size = Vector2(36, 36)
	dec_btn.add_theme_font_size_override("font_size", 18)
	stepper.add_child(dec_btn)

	var inp := LineEdit.new()
	inp.alignment = HORIZONTAL_ALIGNMENT_CENTER
	inp.custom_minimum_size = Vector2(50, 36)
	inp.add_theme_font_size_override("font_size", 14)
	inp.max_length = 3
	_write_weight(inp, initial)
	stepper.add_child(inp)

	var inc_btn := Button.new()
	inc_btn.text = "+"
	inc_btn.custom_minimum_size = Vector2(36, 36)
	inc_btn.add_theme_font_size_override("font_size", 18)
	stepper.add_child(inc_btn)

	dec_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		_write_weight(inp, _read_weight(inp) - 1)
	)
	inc_btn.pressed.connect(func():
		SfxManager.play("ui_click")
		_write_weight(inp, _read_weight(inp) + 1)
	)
	inp.text_submitted.connect(func(_t): _write_weight(inp, _read_weight(inp)))
	inp.focus_exited.connect(func(): _write_weight(inp, _read_weight(inp)))

	return {"container": stepper, "dec": dec_btn, "inp": inp, "inc": inc_btn}


static func _read_weight(inp: LineEdit) -> int:
	var t := inp.text.strip_edges()
	if not t.is_valid_int():
		return WEIGHT_MIN
	return clampi(t.to_int(), WEIGHT_MIN, WEIGHT_MAX)


static func _write_weight(inp: LineEdit, val: int) -> void:
	inp.text = str(clampi(val, WEIGHT_MIN, WEIGHT_MAX))


# --- Event handlers ---

func _on_search_changed(text: String) -> void:
	_search_text = text.strip_edges()
	_search_timer.stop()
	_search_timer.start()


func _apply_filter() -> void:
	_commit_all_pending_edits()
	_rebuild()


func _on_folder_arrow_pressed(folder: String) -> void:
	# Flush any unsubmitted stepper edits before tearing down the rows.
	_commit_all_pending_edits()
	_collapsed_folders[folder] = not _collapsed_folders.get(folder, false)
	_save_state()
	_rebuild()
	# The rebuild freed every row, including the arrow that was just pressed;
	# put the pad cursor back on this folder's fresh arrow so navigation
	# continues in place instead of dying with the freed control.
	if GamepadHelper.is_using_gamepad() and _folder_rows.has(folder):
		(_folder_rows[folder]["arrow_btn"] as Button).grab_focus()


func _commit_all_pending_edits() -> void:
	for dn in _deck_rows.keys():
		_persist_deck_weight(dn)
	for fp in _folder_rows.keys():
		var ui: Dictionary = _folder_rows[fp]
		if ui.has("check"):
			_persist_folder_weight(fp)


func _on_folder_check_toggled(_pressed: bool, folder: String) -> void:
	_persist_folder_weight(folder)
	_apply_folder_takeover_to_all()
	_refresh_select_all_label()


func _on_deck_check_toggled(_pressed: bool, deck_name: String) -> void:
	_persist_deck_weight(deck_name)
	_refresh_select_all_label()


func _persist_deck_weight(deck_name: String) -> void:
	var ui: Dictionary = _deck_rows.get(deck_name, {})
	if ui.is_empty() or not ui.has("check"):
		return
	var check: CheckBox = ui["check"]
	var inp: LineEdit = ui["inp"]
	if check.button_pressed:
		_deck_weights[deck_name] = _read_weight(inp)
	else:
		_deck_weights[deck_name] = 0
	_refresh_folder_count(String(ui.get("folder", "")))
	_refresh_all_percentages()


func _persist_folder_weight(folder: String) -> void:
	var ui: Dictionary = _folder_rows.get(folder, {})
	if ui.is_empty() or not ui.has("check"):
		return
	var check: CheckBox = ui["check"]
	var inp: LineEdit = ui["inp"]
	if check.button_pressed:
		_folder_weights[folder] = _read_weight(inp)
	else:
		_folder_weights[folder] = 0
	_refresh_folder_count(folder)
	_apply_folder_takeover_to_all()  # also refreshes percentages


func _refresh_folder_count(folder: String) -> void:
	var ui: Dictionary = _folder_rows.get(folder, {})
	if ui.is_empty() or not ui.has("count_label"):
		return
	var label: Label = ui["count_label"]
	# Folder enabled → don't show selection count (folder takes over).
	var folder_enabled := false
	if ui.has("check"):
		folder_enabled = (ui["check"] as CheckBox).button_pressed
	if folder_enabled:
		label.text = ""
		return
	var selected := 0
	var total := 0
	for entry in _entries:
		if entry["folder"] != folder:
			continue
		var dn: String = entry["name"]
		if not _is_deck_eligible(dn):
			continue
		total += 1
		var has_entry: bool = _deck_weights.has(dn)
		var w: int = int(_deck_weights.get(dn, 1))
		if (not has_entry) or w > 0:
			selected += 1
	if selected > 0 and selected < total:
		label.text = "(%d / %d)" % [selected, total]
	elif selected > 0 and selected == total:
		label.text = "(%d)" % total
	elif bool(ui.get("collapsed", false)):
		label.text = "(0 / %d)" % total
	else:
		label.text = ""


func _on_select_all_pressed() -> void:
	SfxManager.play("ui_click")
	# Look at all visible deck rows whose folder is NOT enabled.
	var any_unchecked := false
	for dn in _deck_rows:
		var ui: Dictionary = _deck_rows[dn]
		var folder: String = ui["folder"]
		if _is_folder_enabled(folder):
			continue
		if not (ui["check"] as CheckBox).button_pressed:
			any_unchecked = true
			break
	var new_state := any_unchecked
	for dn in _deck_rows:
		var ui: Dictionary = _deck_rows[dn]
		if _is_folder_enabled(ui["folder"]):
			continue
		(ui["check"] as CheckBox).set_pressed_no_signal(new_state)
	_refresh_select_all_label()


func _on_reset_weights_pressed() -> void:
	SfxManager.play("ui_click")
	for dn in _deck_rows:
		var ui: Dictionary = _deck_rows[dn]
		if (ui["check"] as CheckBox).button_pressed:
			_write_weight(ui["inp"], 1)
	for fp in _folder_rows:
		var ui: Dictionary = _folder_rows[fp]
		if not ui.has("check"):
			continue
		if (ui["check"] as CheckBox).button_pressed:
			_write_weight(ui["inp"], 1)


# --- Folder-takeover ---

func _is_folder_enabled(folder: String) -> bool:
	var ui: Dictionary = _folder_rows.get(folder, {})
	if ui.is_empty() or not ui.has("check"):
		# Folder is not currently rendered — fall back to the saved weight.
		return int(_folder_weights.get(folder, 0)) > 0
	return (ui["check"] as CheckBox).button_pressed


# --- Format eligibility ---

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


func _folder_has_any_eligible(folder: String) -> bool:
	if _format_id.is_empty():
		return true
	for entry in _entries:
		if entry["folder"] == folder and _is_deck_eligible(entry["name"]):
			return true
	return false


func _apply_folder_takeover_to_all() -> void:
	# When a folder is enabled, dim its deck rows (folder takes over) but keep
	# them visible so users can still see what's inside. Also dim rows that
	# fail the current format filter, and dim folders whose every deck is
	# ineligible.
	for dn in _deck_rows:
		var ui: Dictionary = _deck_rows[dn]
		(ui["container"] as Control).visible = true
		var eligible := _is_deck_eligible(dn)
		var dimmed := _is_folder_enabled(ui["folder"]) or not eligible
		_set_row_dimmed(ui, dimmed)
		if ui.has("check"):
			(ui["check"] as CheckBox).tooltip_text = tr("STR_MENU_BOT_DECK_NOT_IN_FORMAT") if not eligible else dn
	for fp in _folder_rows:
		var ui: Dictionary = _folder_rows[fp]
		_set_row_dimmed(ui, not _folder_has_any_eligible(fp))
	_refresh_all_percentages()


func _set_row_dimmed(ui: Dictionary, dimmed: bool) -> void:
	var container: Control = ui["container"]
	container.modulate = Color(1, 1, 1, 0.45) if dimmed else Color(1, 1, 1, 1)
	if ui.has("check"):
		(ui["check"] as CheckBox).disabled = dimmed or not _random_enabled
	if ui.has("dec"):
		(ui["dec"] as Button).disabled = dimmed or not _random_enabled
	if ui.has("inc"):
		(ui["inc"] as Button).disabled = dimmed or not _random_enabled
	if ui.has("inp"):
		(ui["inp"] as LineEdit).editable = (not dimmed) and _random_enabled


func _compute_total_weight() -> int:
	var total := 0
	# Enabled folders contribute their weight — but only if at least one deck
	# inside is eligible under the current format filter.
	for fp in _folder_weights:
		var fw := int(_folder_weights[fp])
		if fw > 0 and _folder_has_any_eligible(fp):
			total += fw
	# Individual decks contribute only when their folder is NOT enabled AND
	# they're eligible.
	for entry in _entries:
		var f: String = entry["folder"]
		if int(_folder_weights.get(f, 0)) > 0:
			continue
		var dn: String = entry["name"]
		if not _is_deck_eligible(dn):
			continue
		var has_entry: bool = _deck_weights.has(dn)
		var w: int = 1
		if has_entry:
			w = int(_deck_weights[dn])
		if w > 0:
			total += w
	return total


func _refresh_all_percentages() -> void:
	var total := _compute_total_weight()
	# Folder rows: show pct only when folder is enabled AND it has at least
	# one deck eligible under the current format filter.
	for fp in _folder_rows:
		var ui: Dictionary = _folder_rows[fp]
		if not ui.has("pct_label"):
			continue
		var label: Label = ui["pct_label"]
		var fw := int(_folder_weights.get(fp, 0))
		if fw > 0 and total > 0 and _folder_has_any_eligible(fp):
			label.text = "%.2f%%" % (100.0 * float(fw) / float(total))
		else:
			label.text = ""
	# Deck rows: show pct only when its folder is NOT enabled, the deck is
	# enabled, AND the deck is eligible under the current format filter.
	for dn in _deck_rows:
		var ui: Dictionary = _deck_rows[dn]
		if not ui.has("pct_label"):
			continue
		var label: Label = ui["pct_label"]
		var folder: String = ui.get("folder", "")
		if int(_folder_weights.get(folder, 0)) > 0:
			label.text = ""
			continue
		if not _is_deck_eligible(dn):
			label.text = ""
			continue
		var has_entry: bool = _deck_weights.has(dn)
		var w: int = 1
		if has_entry:
			w = int(_deck_weights[dn])
		if w > 0 and total > 0:
			label.text = "%.2f%%" % (100.0 * float(w) / float(total))
		else:
			label.text = ""


# --- Random-enabled gating ---

func _apply_random_enabled_to_all() -> void:
	if _select_all_btn != null:
		_select_all_btn.disabled = not _random_enabled
	if _reset_weights_btn != null:
		_reset_weights_btn.disabled = not _random_enabled
	if _search_edit != null:
		_search_edit.editable = _random_enabled
	# Row dim state is the canonical "folder takeover OR ineligible" + the
	# _random_enabled gate baked into _set_row_dimmed; delegate the whole pass.
	_apply_folder_takeover_to_all()


func _refresh_select_all_label() -> void:
	if _select_all_btn == null:
		return
	var any_unchecked := false
	for dn in _deck_rows:
		var ui: Dictionary = _deck_rows[dn]
		if _is_folder_enabled(ui["folder"]):
			continue
		if not (ui["check"] as CheckBox).button_pressed:
			any_unchecked = true
			break
	_select_all_btn.text = tr("STR_MENU_DECK_SELECT_ALL") if any_unchecked else tr("STR_MENU_DECK_UNSELECT_ALL")


# --- Collapse state persistence (shared with DeckListView) ---

func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(STATE_PATH) != OK:
		return
	if not cfg.has_section("collapsed"):
		return
	for key in cfg.get_section_keys("collapsed"):
		_collapsed_folders[key] = cfg.get_value("collapsed", key, false)


func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	if cfg.has_section("collapsed"):
		cfg.erase_section("collapsed")
	for key in _collapsed_folders:
		cfg.set_value("collapsed", key, _collapsed_folders[key])
	cfg.save(STATE_PATH)
