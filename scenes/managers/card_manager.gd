extends Node2D
class_name CardManager

## Manages a collection of Card nodes with automatic layout and positioning

# Signals
signal card_added(card: Control)
signal card_removed(card: Control)
signal cards_reordered()

# Enums
enum LayoutMode {
	HAND_ARC,      # Cards arranged in an arc (typical for player hand)
	GRID,          # Cards in a grid layout
	STACK,         # Cards stacked on top of each other
	HORIZONTAL,    # Cards in a horizontal line
	VERTICAL       # Cards in a vertical line
}

# Export variables
@export var layout_mode: LayoutMode = LayoutMode.HAND_ARC
@export var card_spacing: float = 20.0
@export var max_cards: int = 10
@export var auto_arrange: bool = true
@export_range(0.0, 1.0) var arrange_duration: float = 0.3

# Hand arc specific settings
@export_group("Hand Arc Settings")
@export var arc_radius: float = 600.0
@export var arc_angle: float = 60.0  # Total angle span in degrees
@export var vertical_offset: float = 150.0  # How much lower cards are at the edges

# Grid specific settings
@export_group("Grid Settings")
@export var grid_columns: int = 5
@export var grid_row_spacing: float = 250.0
@export var grid_column_spacing: float = 170.0

# Internal state
var managed_cards: Array[Control] = []
var card_target_positions: Dictionary = {}  # Maps card to its target position
var card_target_rotations: Dictionary = {}  # Maps card to its target rotation
var dragged_card: Control = null  # Currently dragged card
var dragged_card_original_index: int = -1  # Original index of dragged card


func _ready() -> void:
	# Set up initial cards if any children exist
	for child in get_children():
		if child is Control:
			_register_card(child)

	if auto_arrange:
		arrange_cards()


## Add a card to the manager
func add_card(card: Control, animate: bool = true) -> void:
	if managed_cards.size() >= max_cards:
		push_warning("CardManager: Maximum cards reached (%d)" % max_cards)
		return

	if card.get_parent() != self:
		if card.get_parent():
			card.get_parent().remove_child(card)
		add_child(card)

	_register_card(card)
	card_added.emit(card)

	if auto_arrange:
		arrange_cards(animate)


## Remove a card from the manager
func remove_card(card: Control, animate: bool = true) -> void:
	if card not in managed_cards:
		push_warning("CardManager: Card not found in manager")
		return

	managed_cards.erase(card)
	card_target_positions.erase(card)
	card_target_rotations.erase(card)

	# Disconnect signals if they exist
	if card.has_signal("drag_ended") and card.drag_ended.is_connected(_on_card_drag_ended):
		card.drag_ended.disconnect(_on_card_drag_ended)
	if card.has_signal("drag_started") and card.drag_started.is_connected(_on_card_drag_started):
		card.drag_started.disconnect(_on_card_drag_started)

	card_removed.emit(card)

	if auto_arrange:
		arrange_cards(animate)


## Remove card at specific index
func remove_card_at(index: int, animate: bool = true) -> Control:
	if index < 0 or index >= managed_cards.size():
		push_error("CardManager: Invalid index %d" % index)
		return null

	var card = managed_cards[index]
	remove_card(card, animate)
	return card


## Clear all cards from the manager
func clear_cards(destroy: bool = false) -> void:
	for card in managed_cards.duplicate():
		# Disconnect signals
		if card.has_signal("drag_ended") and card.drag_ended.is_connected(_on_card_drag_ended):
			card.drag_ended.disconnect(_on_card_drag_ended)
		if card.has_signal("drag_started") and card.drag_started.is_connected(_on_card_drag_started):
			card.drag_started.disconnect(_on_card_drag_started)

		if destroy:
			card.queue_free()
		else:
			remove_child(card)

	managed_cards.clear()
	card_target_positions.clear()
	card_target_rotations.clear()


## Get all managed cards
func get_cards() -> Array[Control]:
	return managed_cards.duplicate()


## Get card count
func get_card_count() -> int:
	return managed_cards.size()


## Get card at index
func get_card_at(index: int) -> Control:
	if index < 0 or index >= managed_cards.size():
		return null
	return managed_cards[index]


## Check if manager is full
func is_full() -> bool:
	return managed_cards.size() >= max_cards


## Arrange all cards according to current layout mode
func arrange_cards(animate: bool = true) -> void:
	match layout_mode:
		LayoutMode.HAND_ARC:
			_arrange_hand_arc(animate)
		LayoutMode.GRID:
			_arrange_grid(animate)
		LayoutMode.STACK:
			_arrange_stack(animate)
		LayoutMode.HORIZONTAL:
			_arrange_horizontal(animate)
		LayoutMode.VERTICAL:
			_arrange_vertical(animate)

	cards_reordered.emit()


## Private methods

func _register_card(card: Control) -> void:
	if card not in managed_cards:
		managed_cards.append(card)

		# Connect to card drag signals if they exist
		if card.has_signal("drag_ended"):
			card.drag_ended.connect(_on_card_drag_ended.bind(card))
		if card.has_signal("drag_started"):
			card.drag_started.connect(_on_card_drag_started.bind(card))


func _arrange_hand_arc(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return

	var angle_step = arc_angle / max(1, count - 1) if count > 1 else 0
	var start_angle = -arc_angle / 2.0

	for i in range(count):
		var card = managed_cards[i]
		var angle = start_angle + (angle_step * i)
		var angle_rad = deg_to_rad(angle)

		# Calculate position on arc
		var x = sin(angle_rad) * arc_radius
		var y = -cos(angle_rad) * arc_radius + arc_radius - vertical_offset * abs(angle / (arc_angle / 2.0))

		var target_pos = Vector2(x, y)
		var target_rotation = 0.0  # Keep cards upright (no rotation)

		# Set z_index so cards can overlap naturally (left cards behind right cards)
		card.z_index = i

		_move_card_to_position(card, target_pos, target_rotation, animate)


func _arrange_grid(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return

	var rows = ceili(float(count) / float(grid_columns))
	var start_x = -(grid_columns - 1) * grid_column_spacing / 2.0
	var start_y = -(rows - 1) * grid_row_spacing / 2.0

	for i in range(count):
		var card = managed_cards[i]
		var col = i % grid_columns
		var row = i / grid_columns

		var target_pos = Vector2(
			start_x + col * grid_column_spacing,
			start_y + row * grid_row_spacing
		)

		card.z_index = i  # Maintain reading order

		_move_card_to_position(card, target_pos, 0.0, animate)


func _arrange_stack(animate: bool) -> void:
	for i in range(managed_cards.size()):
		var card = managed_cards[i]
		# Slight offset for stacked appearance
		var target_pos = Vector2(i * 2, i * 2)
		card.z_index = i
		_move_card_to_position(card, target_pos, 0.0, animate)


func _arrange_horizontal(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return

	var total_width = (count - 1) * card_spacing
	var start_x = -total_width / 2.0

	for i in range(count):
		var card = managed_cards[i]
		var target_pos = Vector2(start_x + i * card_spacing, 0)
		card.z_index = i
		_move_card_to_position(card, target_pos, 0.0, animate)


func _arrange_vertical(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return

	var total_height = (count - 1) * card_spacing
	var start_y = -total_height / 2.0

	for i in range(count):
		var card = managed_cards[i]
		var target_pos = Vector2(0, start_y + i * card_spacing)
		card.z_index = i
		_move_card_to_position(card, target_pos, 0.0, animate)


func _move_card_to_position(card: Control, target_pos: Vector2, target_rotation: float, animate: bool) -> void:
	# Store the target position and rotation for this card
	card_target_positions[card] = target_pos
	card_target_rotations[card] = target_rotation

	if animate and arrange_duration > 0:
		# Use the card's built-in return_to_position if available
		if card.has_method("return_to_position"):
			card.return_to_position(target_pos, arrange_duration)
			# Handle rotation separately
			if target_rotation != 0:
				var tween = create_tween()
				tween.tween_property(card, "rotation", target_rotation, arrange_duration)
		else:
			var tween = create_tween()
			tween.set_parallel(true)
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(card, "position", target_pos, arrange_duration)
			if target_rotation != 0:
				tween.tween_property(card, "rotation", target_rotation, arrange_duration)
	else:
		card.position = target_pos
		card.rotation = target_rotation


## Signal handlers

func _on_card_drag_started(card: Control) -> void:
	# Store dragging state
	if card in managed_cards:
		dragged_card = card
		dragged_card_original_index = managed_cards.find(card)
		card.z_index = 100


func _on_card_drag_ended(card: Control) -> void:
	if card not in managed_cards:
		return

	# Calculate the new index based on card's current position
	var new_index = _calculate_insertion_index(card)

	# Reorder if the position changed
	if new_index != dragged_card_original_index:
		# Remove from old position
		managed_cards.erase(card)
		# Insert at new position
		managed_cards.insert(new_index, card)

		# Emit reordered signal
		cards_reordered.emit()

	# Clear dragging state
	dragged_card = null
	dragged_card_original_index = -1

	# Rearrange all cards with animation (this will reset positions, rotations, z-index)
	arrange_cards(true)


## Helper methods for reordering

func _calculate_insertion_index(card: Control) -> int:
	"""Calculate where the card should be inserted based on its current position"""
	# Build a list of cards excluding the dragged card
	var other_cards: Array[Control] = []
	for c in managed_cards:
		if c != card:
			other_cards.append(c)

	if other_cards.is_empty():
		return 0

	var card_center = card.global_position + card.size * card.scale / 2.0
	var local_pos = to_local(card_center)

	# Check each position and insert before the first card that's "after" us
	for i in range(other_cards.size()):
		var other_card = other_cards[i]
		if other_card not in card_target_positions:
			continue

		var target_pos = card_target_positions[other_card]

		# For horizontal layouts (hand arc, horizontal line)
		if layout_mode == LayoutMode.HAND_ARC or layout_mode == LayoutMode.HORIZONTAL:
			if local_pos.x < target_pos.x:
				return i  # Insert before this card

		# For vertical layout
		elif layout_mode == LayoutMode.VERTICAL:
			if local_pos.y < target_pos.y:
				return i  # Insert before this card

		# For grid layout, use a combination
		elif layout_mode == LayoutMode.GRID:
			# Compare by row first, then column
			if local_pos.y < target_pos.y - grid_row_spacing / 2:
				return i
			elif local_pos.y < target_pos.y + grid_row_spacing / 2:
				if local_pos.x < target_pos.x:
					return i

	# If we didn't insert before any card, insert at the end
	return other_cards.size()
