extends Control
class_name Slot

## A slot that can hold a single Card, with zone metadata for the TCG board.
## The visual area (Background) maintains the card aspect ratio (5:7) within
## whatever space the parent container allocates.

const CARD_RATIO := 5.0 / 7.0  # width / height

# Signals
signal card_placed(card: Control)
signal card_removed(card: Control)
signal hover_started()
signal hover_ended()
signal slot_clicked(zone_number: int, player_id: int)
signal slot_right_clicked(zone_number: int, player_id: int)

# Export variables
@export var slot_color: Color = Color(0.2, 0.2, 0.3, 0.5)
@export var highlight_color: Color = Color(0.3, 0.5, 0.8, 0.7)
@export var occupied_color: Color = Color(0.2, 0.4, 0.3, 0.5)
@export var snap_duration: float = 0.3
@export var accept_cards: bool = true
@export var landscape: bool = false  # When true, uses 7:5 (landscape) aspect ratio

# Zone metadata
@export var zone_number: int = 0  # 1-8 for battle zones, 0 for other
@export var slot_type: String = "battle_zone"  # battle_zone, strategy_zone, monster, deck, discard
@export var player_id: int = 0

# Internal state
var held_card: Control = null
var is_highlighted: bool = false
var is_occupied: bool = false
var has_monster_marker: bool = false
var in_selection_mode: bool = false  # When true, allows highlighting even if occupied
var _content_rect: Rect2 = Rect2()


func _ready() -> void:
	_update_content_rect()
	_update_visual_state()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	# Ensure slot children don't block mouse events from reaching this Control
	if has_node("Background"):
		$Background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has_node("Label"):
		$Label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_content_rect()
		_update_visual_state()
		_refit_held_card()


func _update_content_rect() -> void:
	var w := size.x
	var h := size.y
	if h <= 0 or w <= 0:
		_content_rect = Rect2(0, 0, w, h)
		return

	var ratio := (1.0 / CARD_RATIO) if landscape else CARD_RATIO
	var target_w := h * ratio
	if target_w <= w:
		# Height is the constraint — center horizontally
		_content_rect = Rect2((w - target_w) / 2.0, 0, target_w, h)
	else:
		# Width is the constraint — center vertically
		var target_h := w / ratio
		_content_rect = Rect2(0, (h - target_h) / 2.0, w, target_h)


func is_empty() -> bool:
	return held_card == null


func has_card() -> bool:
	return held_card != null


func get_card() -> Control:
	return held_card


func place_card(card: Control, animate: bool = true) -> bool:
	if not accept_cards:
		return false

	if held_card != null:
		push_warning("Slot: Attempting to place card in occupied slot")
		return false

	if not card:
		push_error("Slot: Attempted to place null card")
		return false

	if card.get_parent():
		card.get_parent().remove_child(card)

	add_child(card)
	held_card = card
	is_occupied = true

	_fit_card_in_slot(card, animate)

	card.z_index = 0
	# Make card and all children transparent to mouse so slot handles all input
	_set_mouse_filter_recursive(card, Control.MOUSE_FILTER_IGNORE)

	if card.has_signal("drag_started"):
		card.drag_started.connect(_on_card_drag_started)
	if card.has_signal("drag_ended"):
		card.drag_ended.connect(_on_card_drag_ended)

	_update_visual_state()
	card_placed.emit(card)

	return true


func _refit_held_card() -> void:
	if held_card:
		_fit_card_in_slot(held_card, false)


func _fit_card_in_slot(card: Control, animate: bool) -> void:
	var padding := 4.0
	var available := _content_rect.size - Vector2(padding * 2, padding * 2)
	if landscape:
		# Portrait card rotated 90° CW to appear sideways in landscape slot
		var card_h := minf(available.x, available.y * 7.0 / 5.0)
		var card_w := card_h * CARD_RATIO  # 5:7 portrait ratio
		var target_size := Vector2(card_w, card_h)
		card.custom_minimum_size = Vector2.ZERO
		card.size = target_size
		card.pivot_offset = target_size / 2.0
		card.scale = Vector2.ONE
		card.set("original_scale", Vector2.ONE)
		card.rotation = deg_to_rad(-90)
		var center := _content_rect.position + _content_rect.size / 2.0
		card.position = center - target_size / 2.0
	else:
		card.custom_minimum_size = Vector2.ZERO
		card.size = available
		card.pivot_offset = available / 2.0
		card.scale = Vector2.ONE
		card.set("original_scale", Vector2.ONE)
		card.rotation = 0.0
		var target_pos := _content_rect.position + Vector2(padding, padding)
		if animate and card.has_method("return_to_position"):
			card.return_to_position(target_pos, snap_duration)
		else:
			card.position = target_pos


func remove_card(destroy: bool = false) -> Control:
	if held_card == null:
		return null

	var card = held_card

	if card.has_signal("drag_started") and card.drag_started.is_connected(_on_card_drag_started):
		card.drag_started.disconnect(_on_card_drag_started)
	if card.has_signal("drag_ended") and card.drag_ended.is_connected(_on_card_drag_ended):
		card.drag_ended.disconnect(_on_card_drag_ended)

	held_card = null
	is_occupied = false
	card.rotation = 0.0

	if destroy:
		card.queue_free()
	else:
		_set_mouse_filter_recursive(card, Control.MOUSE_FILTER_STOP)
		remove_child(card)

	_update_visual_state()
	card_removed.emit(card)

	return card


func try_accept_card(card: Control) -> bool:
	if not accept_cards or is_occupied:
		return false
	return place_card(card, true)


func set_highlighted(highlighted: bool) -> void:
	is_highlighted = highlighted
	_update_visual_state()
	if highlighted:
		hover_started.emit()
	else:
		hover_ended.emit()


func set_monster_marker(is_marked: bool) -> void:
	has_monster_marker = is_marked
	_update_visual_state()


func _update_visual_state() -> void:
	if not is_node_ready():
		return

	var background = $Background as Panel
	if not background:
		return

	# Position background to the content rect (card aspect ratio area)
	background.position = _content_rect.position
	background.size = _content_rect.size

	var target_color: Color
	if has_monster_marker:
		target_color = Color(0.8, 0.5, 0.1, 0.7)  # Orange for monster position
	elif is_occupied:
		target_color = occupied_color
	elif is_highlighted:
		target_color = highlight_color
	else:
		target_color = slot_color

	var style = background.get("theme_override_styles/panel")
	if not style or not style is StyleBoxFlat:
		style = StyleBoxFlat.new()
		background.add_theme_stylebox_override("panel", style)

	style.bg_color = target_color
	style.border_color = Color(1, 1, 1, 0.3)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8

	if has_node("Label"):
		var lbl: Label = $Label
		# Center label within the content rect
		lbl.position = _content_rect.position
		lbl.size = _content_rect.size
		if has_monster_marker and not is_occupied:
			lbl.text = "MONSTER"
			lbl.visible = true
		elif zone_number > 0 and not is_occupied:
			lbl.text = "Z%d" % zone_number
			lbl.visible = true
		else:
			lbl.visible = not is_occupied


func _on_mouse_entered() -> void:
	if accept_cards and (is_empty() or in_selection_mode):
		set_highlighted(true)


func _on_mouse_exited() -> void:
	set_highlighted(false)


func _on_card_drag_started() -> void:
	pass


func _on_card_drag_ended() -> void:
	var card = held_card
	if not card:
		return

	var mouse_pos = get_global_mouse_position()
	var slot_rect = Rect2(global_position, size)

	if not slot_rect.has_point(mouse_pos):
		if card.has_signal("drag_started") and card.drag_started.is_connected(_on_card_drag_started):
			card.drag_started.disconnect(_on_card_drag_started)
		if card.has_signal("drag_ended") and card.drag_ended.is_connected(_on_card_drag_ended):
			card.drag_ended.disconnect(_on_card_drag_ended)

		held_card = null
		is_occupied = false
		_update_visual_state()
		card_removed.emit(card)
	else:
		var padding := 4.0
		var target_pos := _content_rect.position + Vector2(padding, padding)
		if card.has_method("return_to_position"):
			card.return_to_position(target_pos, snap_duration)
		else:
			card.position = target_pos


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and held_card != null:
		if event.button_index == MOUSE_BUTTON_LEFT and zone_number > 0:
			slot_clicked.emit(zone_number, player_id)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(zone_number, player_id)


func _set_mouse_filter_recursive(node: Control, filter: MouseFilter) -> void:
	node.mouse_filter = filter
	for child in node.get_children():
		if child is Control:
			_set_mouse_filter_recursive(child, filter)
