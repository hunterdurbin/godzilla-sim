extends ColorRect

## Full-screen zoom of a single card. Self-contained: handles desktop click,
## mobile pinch-to-zoom, drag-to-pan, trackpad magnify gestures internally.
##
## Public API:
##   show_card(card_data, play_cost_modifier := 0)
##   close()                                      # used by game_board ESC
##   signal closed                                # emitted on any dismissal
##   slot_reset_callback (assignable)             # invoked on dismiss to reset
##                                                # board slot input timers
##
## game_board passes a `slot_reset_callback` so the overlay can clear hover
## timers on PlayerBoard slots when zoom dismisses, without reaching back.

signal closed

const _CARD_SCENE := preload("res://scenes/cards/Card.tscn")
const _PINCH_MAX_SCALE: float = 3.0
const _ZOOM_DRAG_DEADZONE: float = 20.0

@onready var _container: CenterContainer = $CardContainer

var slot_reset_callback: Callable = Callable()

var _pinch_active: bool = false
var _pinch_used: bool = false
var _pinch_start_distance: float = 0.0
var _pinch_start_scale: float = 1.0
var _pinch_touches: Dictionary = {}
var _zoom_shown_frame: int = -1
var _zoom_dragging: bool = false
var _zoom_drag_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	visible = false
	z_index = 200
	gui_input.connect(_on_overlay_gui_input)


func show_card(card_data: Dictionary, play_cost_modifier: int = 0) -> void:
	_clear_container()
	var card: Control = _CARD_SCENE.instantiate()
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
		# Portrait 405x567 rotated -90° to appear landscape inside the wrapper.
		var portrait_size := Vector2(405, 567)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(portrait_size.y, portrait_size.x)
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_container.add_child(wrapper)
		card.custom_minimum_size = Vector2.ZERO
		card.size = portrait_size
		card.pivot_offset = portrait_size / 2.0
		card.rotation = deg_to_rad(-90)
		card.position = Vector2(
			(wrapper.custom_minimum_size.x - portrait_size.x) / 2.0,
			(wrapper.custom_minimum_size.y - portrait_size.y) / 2.0,
		)
		wrapper.add_child(card)
	else:
		card.custom_minimum_size = Vector2(405, 567)
		_container.add_child(card)
	if card.has_method("update_play_cost_badge_layout"):
		card.update_play_cost_badge_layout()
	visible = true
	_zoom_shown_frame = Engine.get_process_frames()


func close() -> void:
	visible = false
	_container.scale = Vector2.ONE
	_container.position = Vector2.ZERO
	_pinch_touches.clear()
	_pinch_active = false
	_pinch_used = false
	_zoom_dragging = false
	_clear_container()
	if slot_reset_callback.is_valid():
		slot_reset_callback.call()
	closed.emit()


func _clear_container() -> void:
	for child in _container.get_children():
		child.queue_free()


func _on_overlay_gui_input(event: InputEvent) -> void:
	if TouchHelper.is_touch_device():
		return # Touch dismiss handled by _unhandled_input ScreenTouch handler
	if (Engine.get_process_frames() - _zoom_shown_frame) <= 2:
		return
	if event is InputEventMouseButton and event.pressed:
		close()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var fresh: bool = (Engine.get_process_frames() - _zoom_shown_frame) <= 2

	if event is InputEventScreenTouch:
		if event.pressed:
			if fresh:
				get_viewport().set_input_as_handled()
				return
			_pinch_touches[event.index] = event.position
			if _pinch_touches.size() == 1:
				_zoom_drag_start = event.position
				_zoom_dragging = false
			elif _pinch_touches.size() == 2:
				_zoom_dragging = false
				var points: Array = _pinch_touches.values()
				_pinch_start_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)
				_pinch_start_scale = _container.scale.x
				_pinch_active = true
				_pinch_used = true
			get_viewport().set_input_as_handled()
		else:
			if not _pinch_touches.has(event.index):
				get_viewport().set_input_as_handled()
				return
			_pinch_touches.erase(event.index)
			if _pinch_active:
				_pinch_active = _pinch_touches.size() >= 2
			elif _pinch_touches.is_empty():
				if _pinch_used or _zoom_dragging:
					_pinch_used = false
					_zoom_dragging = false
				else:
					close()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		var old_pos: Vector2 = _pinch_touches.get(event.index, event.position)
		_pinch_touches[event.index] = event.position
		if _pinch_active and _pinch_touches.size() >= 2:
			var keys: Array = _pinch_touches.keys()
			var other_idx: int = keys[0] if keys[1] == event.index else keys[1]
			var other_pos: Vector2 = _pinch_touches[other_idx]
			var old_midpoint: Vector2 = (old_pos + other_pos) / 2.0
			var new_midpoint: Vector2 = (_pinch_touches[event.index] + other_pos) / 2.0
			_container.position += new_midpoint - old_midpoint
			var points: Array = _pinch_touches.values()
			var dist: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
			if _pinch_start_distance > 0.0:
				var new_scale: float = clampf(_pinch_start_scale * dist / _pinch_start_distance, 1.0, _PINCH_MAX_SCALE)
				_container.scale = Vector2(new_scale, new_scale)
				_container.pivot_offset = _container.size / 2.0
		elif _pinch_touches.size() == 1:
			if not _zoom_dragging:
				if event.position.distance_to(_zoom_drag_start) > _ZOOM_DRAG_DEADZONE:
					_zoom_dragging = true
			if _zoom_dragging:
				_container.position += event.position - old_pos
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMagnifyGesture:
		_apply_zoom(event.factor)
		get_viewport().set_input_as_handled()
		return

	# Desktop click dismiss (skip emulated mouse on touch — ScreenTouch above)
	if not fresh and event is InputEventMouseButton and event.pressed:
		if TouchHelper.is_touch_device():
			get_viewport().set_input_as_handled()
			return
		close()
		get_viewport().set_input_as_handled()


func _apply_zoom(factor: float) -> void:
	var new_scale: float = clampf(_container.scale.x * factor, 1.0, _PINCH_MAX_SCALE)
	_container.scale = Vector2(new_scale, new_scale)
	_container.pivot_offset = _container.size / 2.0
