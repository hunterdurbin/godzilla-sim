extends Control
class_name Slot

## A slot that can hold a single Card, with zone metadata for the TCG board

# Signals
signal card_placed(card: Control)
signal card_removed(card: Control)
signal hover_started()
signal hover_ended()

# Export variables
@export var slot_color: Color = Color(0.2, 0.2, 0.3, 0.5)
@export var highlight_color: Color = Color(0.3, 0.5, 0.8, 0.7)
@export var occupied_color: Color = Color(0.2, 0.4, 0.3, 0.5)
@export var snap_duration: float = 0.3
@export var accept_cards: bool = true

# Zone metadata
@export var zone_number: int = 0  # 1-8 for battle zones, 0 for other
@export var slot_type: String = "battle_zone"  # battle_zone, strategy_zone, monster, deck, discard
@export var player_id: int = 0

# Internal state
var held_card: Control = null
var is_highlighted: bool = false
var is_occupied: bool = false
var has_monster_marker: bool = false


func _ready() -> void:
	_update_visual_state()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


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

	# Scale card to fit within this slot (with 4px padding)
	var padding := 4.0
	var available := size - Vector2(padding * 2, padding * 2)
	var card_base_size: Vector2 = card.size if card.size.x > 0 else Vector2(150, 210)
	var scale_factor: float = minf(available.x / card_base_size.x, available.y / card_base_size.y)
	scale_factor = minf(scale_factor, 1.0)  # Never scale up
	card.scale = Vector2(scale_factor, scale_factor)
	if "original_scale" in card:
		card.original_scale = card.scale

	var scaled_size: Vector2 = card_base_size * scale_factor
	var target_pos: Vector2 = (size - scaled_size) / 2.0

	if animate and card.has_method("return_to_position"):
		card.return_to_position(target_pos, snap_duration)
	else:
		card.position = target_pos

	card.z_index = 0

	if card.has_signal("drag_started"):
		card.drag_started.connect(_on_card_drag_started)
	if card.has_signal("drag_ended"):
		card.drag_ended.connect(_on_card_drag_ended)

	_update_visual_state()
	card_placed.emit(card)

	return true


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

	if destroy:
		card.queue_free()
	else:
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
		if has_monster_marker and not is_occupied:
			$Label.text = "MONSTER"
			$Label.visible = true
		elif zone_number > 0 and not is_occupied:
			$Label.text = "Z%d" % zone_number
			$Label.visible = true
		else:
			$Label.visible = not is_occupied


func _on_mouse_entered() -> void:
	if is_empty() and accept_cards:
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
		var target_pos = size / 2.0 - (card.size * card.scale) / 2.0
		if card.has_method("return_to_position"):
			card.return_to_position(target_pos, snap_duration)
		else:
			card.position = target_pos
