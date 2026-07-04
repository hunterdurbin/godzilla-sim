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
@onready var _sources_list: VBoxContainer = $ModifierSourcesPanel/Margin/ModifierList

## Set by the board: called after the zoom closes (resets slot input state
## so no timers or pending clicks carry over).
var on_hidden: Callable = Callable()

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


func show_card(card_data: Dictionary, play_cost_modifier: int = 0, modifier_entries: Array = []) -> void:
	# Clear any existing zoomed card
	for child in _container.get_children():
		child.queue_free()
	_populate_modifier_sources(card_data, modifier_entries)
	var card: Control = CARD_SCENE.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	if card.has_method("set_play_cost_modifier"):
		card.set_play_cost_modifier(play_cost_modifier)
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
	for child in _container.get_children():
		child.queue_free()
	_clear_modifier_sources()
	if on_hidden.is_valid():
		on_hidden.call()


# --- Modifier sources panel ---

func _clear_modifier_sources() -> void:
	_sources_panel.visible = false
	for child in _sources_list.get_children():
		if child.name != "Header":
			child.queue_free()


func _populate_modifier_sources(card_data: Dictionary, entries: Array) -> void:
	_clear_modifier_sources()
	if entries.is_empty():
		return
	if TouchHelper.is_touch_device():
		# Bottom-center on touch so the panel doesn't fight the pinch-zoomed card.
		_sources_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_sources_panel.offset_top = -16.0
	var own_template: String = ModifierBreakdown.template_id(card_data)
	for e in entries:
		var label := Label.new()
		label.text = _format_modifier_entry(e, own_template)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sources_list.add_child(label)
	_sources_panel.visible = true


func _format_modifier_entry(entry: Dictionary, own_template: String) -> String:
	var source: String = str(entry.get("source", ""))
	var source_name: String
	if source == own_template:
		source_name = tr("STR_ZOOM_MOD_OWN_EFFECT")
	else:
		source_name = _tr_fallback("CARD_%s_NAME" % source, str(entry.get("source_name", "")))
	var args := {
		"AMT": "%+d" % int(entry.get("amount", 0)),
		"SRC": source_name,
		"ZONE": int(entry.get("zone", -1)) + 1,
	}
	match str(entry.get("stat", "")):
		"cp":
			return tr("STR_ZOOM_MOD_POWER_FMT").format(args)
		"cp_double":
			return tr("STR_ZOOM_MOD_POWER_DOUBLE_FMT").format(args)
		"threat":
			return tr("STR_ZOOM_MOD_THREAT_FMT").format(args)
		"zone_play_rank":
			return tr("STR_ZOOM_MOD_COST_ZONE_FMT").format(args)
		"play_rank":
			return tr("STR_ZOOM_MOD_COST_FMT").format(args)
		"field_rank":
			return tr("STR_ZOOM_MOD_RANK_FMT").format(args)
	return "%s — %s" % [args["AMT"], source_name]


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
					else:
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
		hide_zoom()
		get_viewport().set_input_as_handled()
