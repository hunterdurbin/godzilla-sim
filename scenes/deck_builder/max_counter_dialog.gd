class_name MaxCounterDialog
extends AcceptDialog

## Deck builder "Maximum Counter Power" preview: runs MaxCounterOptimizer
## over the edited deck (chunked across frames so the UI never hitches) and
## renders the winning board as a mini playmat — top row Strategy 1/2 +
## zones 8/7/6, bottom row zones 1-5, matching the real board's own-side
## orientation. Every number shown is the engine's, via MaxCounterState.

const CARD_SCENE := preload("res://scenes/cards/Card.tscn")
const CARD_SIZE := Vector2(150, 210)
const SLOT_WIDTH := 116.0
## Optimizer work per frame while calculating.
const STEP_BUDGET_MSEC := 8

## Top row: strategy slots then front-row zones (indices into result arrays;
## -1/-2 mark strategy slots 0/1). Bottom row: zones 1-5.
const TOP_CELLS: Array = [-1, -2, 7, 6, 5]
const BOTTOM_CELLS: Array = [0, 1, 2, 3, 4]

var _total_label: Label
var _status_label: Label
var _assumptions_label: Label
var _zone_option: OptionButton
var _opp_zone_option: OptionButton
var _rage_option: OptionButton
var _cells: Dictionary = {}  # cell key (int) -> {panel, body, name_label, cp_label}
var _optimizer: MaxCounterOptimizer
var _run_id: int = 0
var _monster_entries: Array = []
var _main_entries: Array = []


func _init() -> void:
	title = tr("STR_DB_MAXCP_TITLE")
	min_size = Vector2i(960, 640)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	_total_label = Label.new()
	_total_label.add_theme_font_size_override("font_size", 24)
	_total_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.1, 1))
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_total_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status_label)

	# Constraint parameters: recompute on any change.
	var param_row := HBoxContainer.new()
	param_row.add_theme_constant_override("separation", 12)
	param_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(param_row)
	_zone_option = _add_param_option(param_row, tr("STR_DB_MAXCP_PARAM_ZONE"), _zone_items())
	_opp_zone_option = _add_param_option(param_row, tr("STR_DB_MAXCP_PARAM_OPP"), _zone_items())
	var rage_items: Array[String] = [tr("STR_DB_MAXCP_AUTO")]
	for r in range(11):
		rage_items.append(str(r))
	_rage_option = _add_param_option(param_row, tr("STR_DB_MAXCP_PARAM_RAGE"), rage_items)

	for row_cells in [TOP_CELLS, BOTTOM_CELLS]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		root.add_child(row)
		for cell in row_cells:
			_cells[cell] = _build_cell(row)

	_assumptions_label = Label.new()
	_assumptions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_assumptions_label.add_theme_font_size_override("font_size", 12)
	_assumptions_label.modulate = Color(1, 1, 1, 0.6)
	root.add_child(_assumptions_label)

	visibility_changed.connect(_on_visibility_changed)


func open(monster_entries: Array, main_entries: Array) -> void:
	_monster_entries = monster_entries
	_main_entries = main_entries
	popup_centered()
	_run_id += 1
	_calculate(monster_entries, main_entries, _run_id)


func _add_param_option(row: HBoxContainer, label_text: String, items: Array[String]) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)
	var opt := OptionButton.new()
	for item in items:
		opt.add_item(item)
	opt.selected = 0
	opt.item_selected.connect(_on_param_changed)
	row.add_child(opt)
	# Dropdown popups are focus contexts of their own (pad B closes the
	# popup, not the dialog) — same registration the deck builder uses.
	GamepadHelper.register_modal(opt.get_popup())
	return opt


func _zone_items() -> Array[String]:
	var items: Array[String] = [tr("STR_DB_MAXCP_ANY")]
	for n in range(1, 9):
		items.append(tr("STR_DB_MAXCP_ZONE_FMT").format({"N": n}))
	return items


func _params() -> Dictionary:
	return {
		"monster_zone": _zone_option.selected,
		"opp_monster_zone": _opp_zone_option.selected,
		"rage": _rage_option.selected - 1,
	}


func _on_param_changed(_index: int) -> void:
	if not visible or _main_entries.is_empty():
		return
	_run_id += 1
	_calculate(_monster_entries, _main_entries, _run_id)


func _calculate(monster_entries: Array, main_entries: Array, run: int) -> void:
	_clear_board()
	_total_label.text = tr("STR_DB_MAXCP_CALC")
	_status_label.text = ""
	_assumptions_label.text = ""
	if main_entries.is_empty():
		_total_label.text = tr("STR_DB_MAXCP_EMPTY")
		return

	_drop_optimizer()
	var optimizer := MaxCounterOptimizer.new()
	_optimizer = optimizer
	optimizer.setup(monster_entries, main_entries, _params())
	var running := true
	while running:
		var start := Time.get_ticks_msec()
		while running and Time.get_ticks_msec() - start < STEP_BUDGET_MSEC:
			running = optimizer.step()
		if running:
			await get_tree().process_frame
			# A newer run started or the dialog closed while we yielded.
			if _run_id != run or not visible:
				if _optimizer == optimizer:
					_drop_optimizer()
				else:
					optimizer.teardown()
				return
	_render(optimizer.result())
	_drop_optimizer()


func _render(result: Dictionary) -> void:
	if result.is_empty():
		_total_label.text = tr("STR_DB_MAXCP_EMPTY")
		return
	_total_label.text = "%s: %s" % [tr("STR_DB_MAXCP_TITLE"), _format_number(result["total_cp"])]
	var monster: Dictionary = result["monster"]
	var monster_idx: int = result["monster_zone"] - 1

	var unders: Dictionary = result.get("unders", {})
	for i in range(8):
		var cell: Dictionary = _cells[i]
		var zone_card: Dictionary = result["zones"][i]
		var zone_label: String = tr("STR_DB_MAXCP_ZONE_FMT").format({"N": i + 1})
		if unders.has(i):
			zone_label += " · " + tr("STR_DB_MAXCP_UNDER")
		if i == monster_idx and not monster.is_empty():
			_fill_cell(cell, monster, "%s · %s" % [tr("STR_TYPE_MONSTER"), zone_label], 0, -1, true)
		elif not zone_card.is_empty():
			_fill_cell(cell, zone_card, zone_label,
				result["zone_cp"][i], result["zone_mods"][i], false)
		else:
			_empty_cell(cell, zone_label)

	for s in range(2):
		var cell: Dictionary = _cells[-1 - s]
		var strategy: Dictionary = result["strategies"][s]
		var label := "%s %d" % [tr("STR_TYPE_STRATEGY"), s + 1]
		if strategy.is_empty():
			_empty_cell(cell, label)
		else:
			var mod: int = result["strategy_cp_mods"][s]
			_fill_cell(cell, strategy, label, mod, mod, false)

	var parts: Array[String] = []
	if _rage_option.selected > 0:
		parts.append(tr("STR_DB_MAXCP_PIN_RAGE").format({"RAGE": result["rage"]}))
	else:
		parts.append(tr("STR_DB_MAXCP_ASSUMPTIONS").format({"RAGE": result["rage"]}))
	if _zone_option.selected > 0:
		parts.append(tr("STR_DB_MAXCP_PIN_ZONE").format({"N": result["monster_zone"]}))
	if _opp_zone_option.selected > 0:
		parts.append(tr("STR_DB_MAXCP_PIN_OPP").format({"N": result["opp_monster_zone"]}))
	else:
		parts.append(tr("STR_DB_MAXCP_BEST_OPP").format({"N": result["opp_monster_zone"]}))
	if result["monster_cp_mod"] != 0:
		parts.append("%s: +%s" % [tr("STR_TYPE_MONSTER"), _format_number(result["monster_cp_mod"])])
	_assumptions_label.text = "  ·  ".join(parts)


# --- Cells ---

func _build_cell(row: HBoxContainer) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SLOT_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.06, 0.9)
	style.border_color = Color(0.9, 0.3, 0.1, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", style)
	row.add_child(panel)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	panel.add_child(body)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	body.add_child(name_label)

	# Mini cards must stay Container-wrapped or Card.tscn snaps to 150x210.
	var wrapper := PanelContainer.new()
	wrapper.custom_minimum_size = CARD_SIZE * ((SLOT_WIDTH - 8.0) / CARD_SIZE.x)
	wrapper.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	wrapper.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.add_child(wrapper)

	var cp_label := Label.new()
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cp_label.add_theme_font_size_override("font_size", 12)
	body.add_child(cp_label)

	return {"panel": panel, "wrapper": wrapper, "name_label": name_label, "cp_label": cp_label}


func _fill_cell(cell: Dictionary, card_data: Dictionary, label: String,
		cp: int, mod: int, is_monster: bool) -> void:
	cell["name_label"].text = label
	var wrapper: PanelContainer = cell["wrapper"]
	var card_node: Control = CARD_SCENE.instantiate()
	card_node.use_custom_art = false
	card_node.skip_effect_load = true
	card_node.set_card_data_dict(card_data)
	card_node.drag_enabled = false
	card_node.custom_minimum_size = Vector2.ZERO
	card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := (SLOT_WIDTH - 8.0) / CARD_SIZE.x
	card_node.scale = Vector2(s, s)
	wrapper.add_child(card_node)
	if mod > 0:
		card_node.set_power_preview(mod)
	if is_monster:
		cell["cp_label"].text = ""
		var style: StyleBoxFlat = cell["panel"].get_theme_stylebox("panel")
		style.border_color = Color(0.9, 0.3, 0.1, 1.0)
		style.set_border_width_all(2)
	else:
		cell["cp_label"].text = _format_number(cp)
	cell["panel"].modulate = Color.WHITE


func _empty_cell(cell: Dictionary, label: String) -> void:
	cell["name_label"].text = label
	cell["cp_label"].text = "—"
	cell["panel"].modulate = Color(1, 1, 1, 0.4)


func _clear_board() -> void:
	for key in _cells:
		var cell: Dictionary = _cells[key]
		for child in cell["wrapper"].get_children():
			child.queue_free()
		var style: StyleBoxFlat = cell["panel"].get_theme_stylebox("panel")
		style.border_color = Color(0.9, 0.3, 0.1, 0.35)
		style.set_border_width_all(1)
		cell["name_label"].text = ""
		cell["cp_label"].text = ""
		cell["panel"].modulate = Color.WHITE


func _drop_optimizer() -> void:
	if _optimizer:
		_optimizer.teardown()
	_optimizer = null


func _on_visibility_changed() -> void:
	if not visible:
		_run_id += 1  # cancels any in-flight calculation


static func _format_number(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if value < 0 else "") + text + out
