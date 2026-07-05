class_name CardZoomOverlayUI
extends ColorRect

## Full-screen card zoom overlay with touch pinch-to-zoom / drag-to-pan,
## trackpad magnify, and click/tap dismiss. The board's _input delegates
## events here via handle_input() so the dismissal/blocking semantics keep
## their exact priority over the rest of the board's input handling.

const CARD_SCENE: PackedScene = preload("res://scenes/cards/Card.tscn")
const PINCH_MAX_SCALE: float = 3.0
const ZOOM_DRAG_DEADZONE: float = 20.0

@onready var _container: CenterContainer = $CardContainer
@onready var _sources_panel: PanelContainer = $ModifierSourcesPanel
@onready var _sources_header: Label = $ModifierSourcesPanel/Margin/Layout/Header
@onready var _sources_scroll: ScrollContainer = $ModifierSourcesPanel/Margin/Layout/Scroll
@onready var _sources_list: VBoxContainer = $ModifierSourcesPanel/Margin/Layout/Scroll/ModifierList

const SOURCE_PREVIEW_SIZE := Vector2(72, 101)
const PANEL_BG := Color(0.06, 0.07, 0.10, 0.9)
const ROW_BG := Color(1.0, 1.0, 1.0, 0.04)
const ROW_BG_OPPONENT := Color(0.5, 0.3, 0.7, 0.22)
const HEADER_COLOR := Color(0.85, 0.85, 0.9)
const SECTION_COLOR := Color(0.55, 0.58, 0.68)
const NAME_COLOR := Color(0.72, 0.72, 0.8)
const NAME_COLOR_OPPONENT := Color(0.78, 0.62, 0.95)
const AMOUNT_GOOD := Color(0.4, 0.9, 0.5)
const AMOUNT_BAD := Color(0.95, 0.45, 0.4)
const AMOUNT_NEUTRAL := Color(0.88, 0.88, 0.93)

## Sections in display order: [tr key, stats included].
const SECTIONS := [
	["STR_ZOOM_MOD_SEC_POWER", ["cp_var_base", "cp", "cp_double"]],
	["STR_ZOOM_MOD_SEC_COST", ["play_rank", "zone_play_rank"]],
	["STR_ZOOM_MOD_SEC_RANK", ["field_rank"]],
	["STR_ZOOM_MOD_SEC_THREAT", ["threat_var_base", "threat"]],
]

## Variable-base rows ("this card's counter power/threat level X is ..."):
## rendered unsigned and neutral (they state the base value, not a delta),
## labeled by stat instead of source, no source-card thumbnail. Cards with a
## fixed printed stat get no base row — that value is on the card art.
const BASE_STATS := {
	"cp_var_base": "STR_ZOOM_MOD_BASE_POWER",
	"threat_var_base": "STR_ZOOM_MOD_BASE_THREAT",
}

## Set by the board: called with a source template id when a modifier row is
## clicked, so the zoom can re-target onto the source card.
var on_source_clicked: Callable = Callable()

# Row hitboxes for manual click routing (the panel is MOUSE_FILTER_IGNORE so
# the overlay's dismiss/pinch input priority stays untouched).
var _source_rows: Array = [] # of {"control": Control, "source": String}

## Set by the board: called after the zoom closes (resets slot input state
## so no timers or pending clicks carry over).
var on_hidden: Callable = Callable()

# Badge-hide toggle: an eyeball button above the "Active modifiers" panel
# that clears the on-card badges (play cost, base power/threat) so the
# printed card text stays readable. Resets to visible on every new zoom.
# The sources panel itself is unaffected.
const EYE_OPEN_ICON: Texture2D = preload("res://assets/icons/eye_open.svg")
const EYE_CLOSED_ICON: Texture2D = preload("res://assets/icons/eye_closed.svg")
var _badge_toggle: PanelContainer
var _badge_toggle_icon: TextureRect
var _badges_hidden: bool = false
var _zoomed_card: Control = null

# Pinch-to-zoom / pan state (touch only)
var _pinch_active: bool = false
var _pinch_used: bool = false # True after any pinch — suppress dismiss until next fresh tap
var _pinch_start_distance: float = 0.0
var _pinch_start_scale: float = 1.0
var _pinch_touches: Dictionary = {} # index → position
var _shown_frame: int = -1 # Frame when overlay was shown (ignore dismiss for 2 frames)
var _dragging: bool = false # Single-finger drag active
var _drag_start: Vector2 = Vector2.ZERO # Touch start position for deadzone check


func _ready() -> void:
	visible = false
	z_index = 200
	gui_input.connect(_on_gui_input)
	# Panel styling matches the effect-stack/choice panels (dark navy, radius 8).
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(8)
	_sources_panel.add_theme_stylebox_override("panel", style)
	_sources_header.add_theme_font_size_override("font_size", 15)
	_sources_header.add_theme_color_override("font_color", HEADER_COLOR)
	_build_badge_toggle()


## Eyeball pill that toggles the zoomed card's badges. MOUSE_FILTER_IGNORE
## like the rest of the overlay — presses are routed manually (see
## _handle_toggle_press) so the dismiss/pinch input priority stays untouched.
func _build_badge_toggle() -> void:
	_badge_toggle = PanelContainer.new()
	_badge_toggle.visible = false
	_badge_toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_badge_toggle.add_theme_stylebox_override("panel", style)
	_badge_toggle_icon = TextureRect.new()
	_badge_toggle_icon.texture = EYE_OPEN_ICON
	_badge_toggle_icon.custom_minimum_size = Vector2(24, 24)
	_badge_toggle_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge_toggle_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_toggle.add_child(_badge_toggle_icon)
	add_child(_badge_toggle)


## Sit the eyeball directly above the "Active modifiers" panel (left-aligned
## with it); with no panel (badges but no modifier entries), fall back to the
## panel's usual right-edge spot. Deferred from show_card so the panel's
## dynamic height has settled.
func _position_badge_toggle() -> void:
	if not _badge_toggle.visible:
		return
	_badge_toggle.reset_size()
	var tsize := _badge_toggle.size
	if _sources_panel.visible:
		var rect := _sources_panel.get_global_rect()
		_badge_toggle.global_position = Vector2(rect.position.x, rect.position.y - tsize.y - 8.0)
	else:
		_badge_toggle.global_position = Vector2(size.x - tsize.x - 20.0, (size.y - tsize.y) / 2.0)


func show_card(card_data: Dictionary, play_cost_modifier: int = 0, modifier_entries: Array = [], power_preview: int = 0, threat_preview: int = -1) -> void:
	OverlayGridUtil.ensure_full_rect(self)
	# Clear any existing zoomed card
	for child in _container.get_children():
		child.queue_free()
	_populate_modifier_sources(card_data, modifier_entries)
	var card: Control = CARD_SCENE.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	if card.has_method("set_play_cost_modifier"):
		card.set_play_cost_modifier(play_cost_modifier)
	if card.has_method("set_power_preview"):
		card.set_power_preview(power_preview)
	if card.has_method("set_threat_preview"):
		card.set_threat_preview(threat_preview)
	card.is_selectable = false
	card.drag_enabled = false
	card.hover_scale = 1.0
	card.hover_lift = 0.0
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var is_strategy: bool = card_data.get("card_type") == CardEnums.CardType.STRATEGY
	if is_strategy:
		# Strategy card: portrait 405x567 rotated -90° to appear as landscape 567x405.
		# Use a wrapper sized to the landscape dimensions so CenterContainer centers correctly.
		var portrait_size := Vector2(405, 567)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(portrait_size.y, portrait_size.x) # 567x405
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_container.add_child(wrapper)
		card.custom_minimum_size = Vector2.ZERO
		card.size = portrait_size
		card.pivot_offset = portrait_size / 2.0
		card.rotation = deg_to_rad(-90)
		# Center the portrait card within the landscape wrapper
		card.position = Vector2(
			(wrapper.custom_minimum_size.x - portrait_size.x) / 2.0,
			(wrapper.custom_minimum_size.y - portrait_size.y) / 2.0
		)
		wrapper.add_child(card)
	else:
		card.custom_minimum_size = Vector2(405, 567)
		_container.add_child(card)
	# Re-orient the badge after rotation was set above (strategy zoom rotates -90°).
	if card.has_method("update_play_cost_badge_layout"):
		card.update_play_cost_badge_layout()
	# Badge-hide toggle: fresh zooms always start with badges visible; only
	# offer the button when there is a badge to hide.
	_zoomed_card = card
	_badges_hidden = false
	_badge_toggle_icon.texture = EYE_OPEN_ICON
	_badge_toggle.visible = play_cost_modifier != 0 or power_preview != 0 or threat_preview >= 0
	call_deferred("_position_badge_toggle")
	visible = true
	_shown_frame = Engine.get_process_frames()


func hide_zoom() -> void:
	visible = false
	_container.scale = Vector2.ONE
	_container.position = Vector2.ZERO
	_pinch_touches.clear()
	_pinch_active = false
	_pinch_used = false
	_dragging = false
	_zoomed_card = null
	_badge_toggle.visible = false
	for child in _container.get_children():
		child.queue_free()
	_clear_modifier_sources()
	if on_hidden.is_valid():
		on_hidden.call()


# --- Modifier sources panel ---

func _clear_modifier_sources() -> void:
	_sources_panel.visible = false
	_source_rows.clear()
	for child in _sources_list.get_children():
		child.queue_free()


func _populate_modifier_sources(card_data: Dictionary, entries: Array) -> void:
	_clear_modifier_sources()
	if entries.is_empty():
		return
	var is_touch := TouchHelper.is_touch_device()
	if is_touch:
		# Bottom-center on touch so the panel doesn't fight the pinch-zoomed card.
		_sources_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_sources_panel.offset_top = -16.0
	var own_template: String = ModifierBreakdown.template_id(card_data)
	var row_count: int = 0
	var section_count: int = 0
	for section in SECTIONS:
		var groups := _grouped_section_entries(entries, section[1])
		if groups.is_empty():
			continue
		section_count += 1
		_sources_list.add_child(_make_section_header(section[0]))
		for group in groups:
			_sources_list.add_child(_make_modifier_row(group, own_template))
			row_count += 1
	# Cap the scrollable height so long lists don't overflow the screen.
	var max_h: float = get_viewport_rect().size.y * (0.4 if is_touch else 0.6)
	var est_h: float = row_count * (SOURCE_PREVIEW_SIZE.y + 14.0) + section_count * 22.0
	_sources_scroll.custom_minimum_size = Vector2(0, minf(est_h, max_h))
	_sources_scroll.scroll_vertical = 0
	_sources_panel.visible = true


## A section's entries as display groups: {stat, amount, source, source_name,
## opp, zones: Array[int]}. Every entry is its own row — each contribution
## (including multiple copies of the same card) must stay visible — EXCEPT
## zone_play_rank, where the per-zone entries are one card's alternative
## zone-specific costs, not cumulative, and merge into a single row.
func _grouped_section_entries(entries: Array, stats: Array) -> Array:
	var groups: Array = []
	var by_key: Dictionary = {}
	for e in entries:
		var stat: String = str(e.get("stat", ""))
		if not stat in stats:
			continue
		var zone: int = int(e.get("zone", -1))
		if stat == "zone_play_rank":
			var key := "%s|%s|%d" % [stat, e.get("source", ""), int(e.get("amount", 0))]
			if by_key.has(key):
				if zone >= 0:
					(by_key[key]["zones"] as Array).append(zone)
				continue
		var group := {
			"stat": stat,
			"amount": int(e.get("amount", 0)),
			"source": str(e.get("source", "")),
			"source_name": str(e.get("source_name", "")),
			"opp": bool(e.get("opp", false)),
			"src_loc": str(e.get("src_loc", "")),
			"zones": [],
		}
		if zone >= 0:
			(group["zones"] as Array).append(zone)
		if stat == "zone_play_rank":
			by_key["%s|%s|%d" % [stat, e.get("source", ""), int(e.get("amount", 0))]] = group
		groups.append(group)
	return groups


func _make_section_header(tr_key: String) -> Label:
	var label := Label.new()
	label.text = tr(tr_key).to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", SECTION_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_modifier_row(group: Dictionary, own_template: String) -> Control:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_BG_OPPONENT if group["opp"] else ROW_BG
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", style)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var is_base_row: bool = BASE_STATS.has(str(group["stat"]))
	if not is_base_row:
		var preview := _make_source_preview(str(group["source"]))
		if preview:
			hbox.add_child(preview)

	var text_box := VBoxContainer.new()
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 1)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_box)

	var amount := Label.new()
	if is_base_row:
		amount.text = "%d" % int(group["amount"])
		amount.add_theme_color_override("font_color", AMOUNT_NEUTRAL)
	else:
		amount.text = "%+d" % int(group["amount"])
		amount.add_theme_color_override("font_color",
			AMOUNT_GOOD if _is_beneficial(str(group["stat"]), int(group["amount"])) else AMOUNT_BAD)
	amount.add_theme_font_size_override("font_size", 16)
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(amount)

	var name_label := Label.new()
	if is_base_row:
		name_label.text = tr(BASE_STATS[str(group["stat"])])
	elif str(group["source"]) == own_template:
		name_label.text = tr("STR_ZOOM_MOD_OWN_EFFECT")
	else:
		name_label.text = _tr_fallback("CARD_%s_NAME" % group["source"], str(group["source_name"]))
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color",
		NAME_COLOR_OPPONENT if group["opp"] else NAME_COLOR)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(name_label)

	var detail := _row_detail_text(group)
	if not detail.is_empty():
		var detail_label := Label.new()
		detail_label.text = detail
		detail_label.add_theme_font_size_override("font_size", 10)
		detail_label.add_theme_color_override("font_color", SECTION_COLOR)
		detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_box.add_child(detail_label)

	_source_rows.append({"control": row, "source": str(group["source"])})
	return row


## Mini render of the source card next to its modifier (same pattern as the
## effect-prompt previews). Returns null when the template id is unknown.
func _make_source_preview(base_id: String) -> Control:
	var dict: Dictionary = CardData.get_card_by_id(base_id)
	if dict.is_empty():
		return null
	var card: Control = CARD_SCENE.instantiate()
	card.skip_effect_load = true
	card.drag_enabled = false
	card.is_selectable = false
	card.hover_scale = 1.0
	card.hover_lift = 0.0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(dict.duplicate(true))
	card.custom_minimum_size = SOURCE_PREVIEW_SIZE
	card.size = SOURCE_PREVIEW_SIZE
	return card


## Detail line under the source name: doubling tag, applicable-zone list for
## zone-specific costs, and the source card's board location.
func _row_detail_text(group: Dictionary) -> String:
	var parts: Array[String] = []
	if group["stat"] == "cp_double":
		parts.append(tr("STR_ZOOM_MOD_DOUBLED"))
	if group["stat"] in ["cp_var_base", "threat_var_base"]:
		# Variable printed base ("X") — resolved by the card's own effect.
		parts.append(tr("STR_ZOOM_MOD_OWN_EFFECT"))
		return " · ".join(parts)
	var zones: Array = group["zones"]
	if group["stat"] == "zone_play_rank" and not zones.is_empty():
		# Zones this cost applies in.
		if zones.size() == 1:
			parts.append(tr("STR_ZOOM_MOD_ZONE_FMT").format({"N": int(zones[0]) + 1}))
		else:
			var nums: Array[String] = []
			for z in zones:
				nums.append(str(int(z) + 1))
			parts.append(tr("STR_ZOOM_MOD_ZONES_FMT").format({"LIST": ", ".join(nums)}))
	var loc := _source_location_text(str(group["src_loc"]))
	if not loc.is_empty():
		parts.append(loc)
	return " · ".join(parts)


## "z<idx>" / "monster" / "strategy" -> localized board-location text.
func _source_location_text(src_loc: String) -> String:
	if src_loc.begins_with("z") and src_loc.length() > 1 and src_loc.substr(1).is_valid_int():
		return tr("STR_ZOOM_MOD_ZONE_FMT").format({"N": src_loc.substr(1).to_int() + 1})
	match src_loc:
		"monster":
			return tr("STR_ZOOM_MOD_SRC_MONSTER")
		"strategy":
			return tr("STR_ZOOM_MOD_SRC_STRATEGY")
	return ""


## Whether the modifier helps the zoomed card's owner (colors the amount).
## Cost reductions are good; power/threat/field-rank reductions are bad.
func _is_beneficial(stat: String, amount: int) -> bool:
	match stat:
		"play_rank", "zone_play_rank":
			return amount < 0
		_:
			return amount >= 0


## Route a click/tap at a screen position to a modifier row. Returns true when
## the point is inside the panel (the event is consumed either way so clicks
## on the panel never dismiss the zoom).
func _handle_panel_press(pos: Vector2) -> bool:
	if not _sources_panel.visible or not _sources_panel.get_global_rect().has_point(pos):
		return false
	for r in _source_rows:
		var control: Control = r["control"]
		if is_instance_valid(control) and control.get_global_rect().has_point(pos):
			if on_source_clicked.is_valid():
				on_source_clicked.call(r["source"])
			break
	return true


## Route a click/tap to the badge-hide toggle. Returns true when the point is
## on the pill (the press is consumed and never dismisses the zoom).
func _handle_toggle_press(pos: Vector2) -> bool:
	if not _badge_toggle.visible or not _badge_toggle.get_global_rect().has_point(pos):
		return false
	_badges_hidden = not _badges_hidden
	if is_instance_valid(_zoomed_card) and _zoomed_card.has_method("set_stat_badges_visible"):
		_zoomed_card.set_stat_badges_visible(not _badges_hidden)
	_badge_toggle_icon.texture = EYE_CLOSED_ICON if _badges_hidden else EYE_OPEN_ICON
	return true


static func _tr_fallback(key: String, fallback: String) -> String:
	var translated: String = TranslationServer.translate(key)
	return fallback if translated == key else translated


## Board _input hook. Returns true when the event was consumed (the board
## then marks it handled and stops processing).
func handle_input(event: InputEvent) -> bool:
	if not visible:
		return false
	var zoom_fresh := (Engine.get_process_frames() - _shown_frame) <= 2

	# Pinch-to-zoom and drag-to-pan on card zoom overlay (touch only)
	if event is InputEventScreenTouch:
		if event.pressed:
			if zoom_fresh:
				pass
			else:
				_pinch_touches[event.index] = event.position
				if _pinch_touches.size() == 1:
					_drag_start = event.position
					_dragging = false
				elif _pinch_touches.size() == 2:
					_dragging = false
					var points: Array = _pinch_touches.values()
					_pinch_start_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)
					_pinch_start_scale = _container.scale.x
					_pinch_active = true
					_pinch_used = true
		else:
			if _pinch_touches.has(event.index):
				_pinch_touches.erase(event.index)
				if _pinch_active:
					_pinch_active = _pinch_touches.size() >= 2
				elif _pinch_touches.is_empty():
					if _pinch_used or _dragging:
						_pinch_used = false
						_dragging = false
					elif _handle_toggle_press(event.position):
						pass
					elif not _handle_panel_press(event.position):
						hide_zoom()
		return true

	if event is InputEventScreenDrag:
		var old_pos: Vector2 = _pinch_touches.get(event.index, event.position)
		_pinch_touches[event.index] = event.position
		if _pinch_active and _pinch_touches.size() >= 2:
			# Two-finger pinch zoom + pan simultaneously
			var points: Array = _pinch_touches.values()
			var keys: Array = _pinch_touches.keys()
			var other_idx: int = keys[0] if keys[1] == event.index else keys[1]
			var other_pos: Vector2 = _pinch_touches[other_idx]
			var old_midpoint: Vector2 = (old_pos + other_pos) / 2.0
			var new_midpoint: Vector2 = (_pinch_touches[event.index] + other_pos) / 2.0
			# Pan by midpoint delta
			_container.position += new_midpoint - old_midpoint
			# Zoom by distance change
			var dist: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
			if _pinch_start_distance > 0.0:
				var new_scale: float = clampf(_pinch_start_scale * dist / _pinch_start_distance, 1.0, PINCH_MAX_SCALE)
				_container.scale = Vector2(new_scale, new_scale)
				_container.pivot_offset = _container.size / 2.0
		elif _pinch_touches.size() == 1:
			# Single-finger drag to pan (with deadzone)
			if not _dragging:
				if event.position.distance_to(_drag_start) > ZOOM_DRAG_DEADZONE:
					_dragging = true
			if _dragging:
				_container.position += event.position - old_pos
		return true

	# Magnify gesture (trackpad pinch) — scales card zoom
	if event is InputEventMagnifyGesture:
		_apply_zoom(event.factor)
		return true

	# Dismiss card zoom on any click (must be first — blocks input from reaching overlays behind)
	# Skip emulated mouse events on touch — ScreenTouch handler above covers dismiss
	if not zoom_fresh and event is InputEventMouseButton and event.pressed:
		# Wheel over the modifier panel scrolls it instead of dismissing.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _sources_panel.visible and _sources_panel.get_global_rect().has_point(event.position):
				var dir: int = 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
				_sources_scroll.scroll_vertical += dir * 40
				return true
		# Clicks on the badge toggle or the modifier panel never dismiss.
		if _handle_toggle_press(event.position):
			return true
		if _handle_panel_press(event.position):
			return true
		if not TouchHelper.is_touch_device():
			hide_zoom()
		return true

	return false


func _apply_zoom(factor: float) -> void:
	var new_scale: float = clampf(_container.scale.x * factor, 1.0, PINCH_MAX_SCALE)
	_container.scale = Vector2(new_scale, new_scale)
	_container.pivot_offset = _container.size / 2.0


func _on_gui_input(event: InputEvent) -> void:
	if TouchHelper.is_touch_device():
		return # Touch dismiss handled by the board _input ScreenTouch hook
	if (Engine.get_process_frames() - _shown_frame) <= 2:
		return
	if event is InputEventMouseButton and event.pressed:
		if _handle_toggle_press(event.global_position):
			get_viewport().set_input_as_handled()
			return
		if _handle_panel_press(event.global_position):
			get_viewport().set_input_as_handled()
			return
		hide_zoom()
		get_viewport().set_input_as_handled()
