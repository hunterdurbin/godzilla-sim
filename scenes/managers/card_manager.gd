extends Node2D
class_name CardManager

## Manages a collection of Card nodes with automatic layout and positioning

# Signals
signal card_added(card: Control)
signal card_removed(card: Control)
signal cards_reordered()
signal card_selected(card: Control, index: int)
signal hand_card_drag_started(card: Control)
signal hand_card_drag_ended(card: Control)
signal hand_card_right_clicked(card: Control)

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
@export var max_cards: int = 0  # 0 = unlimited
@export var auto_arrange: bool = true
@export_range(0.0, 1.0) var arrange_duration: float = 0.3
@export var max_width: float = 0.0  # Maximum total width for card layout (0 = unlimited)

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
var drop_handled: bool = false  # Set by external listeners to prevent reordering
var _drop_handled_card: Control = null  # Last drag whose drop was handled externally
var selection_mode: bool = false  # When true, clicking selects instead of dragging
var selectable_indices: Array[int] = []  # Which card indices are selectable
var _drag_preview_index: int = -1  # Where the dragged card would be inserted


func _ready() -> void:
	# Set up initial cards if any children exist
	for child in get_children():
		if child is Control:
			_register_card(child)

	if auto_arrange:
		arrange_cards()


func _process(_delta: float) -> void:
	if not dragged_card or not is_instance_valid(dragged_card):
		return
	var new_index := _calculate_insertion_index(dragged_card)
	if new_index != _drag_preview_index:
		_drag_preview_index = new_index
		_arrange_with_drag_gap(new_index)


## Add a card to the manager
func add_card(card: Control, animate: bool = true) -> void:
	if max_cards > 0 and managed_cards.size() >= max_cards:
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
	return max_cards > 0 and managed_cards.size() >= max_cards


## Arrange all cards according to current layout mode
func arrange_cards(animate: bool = true) -> void:
	# Sync scene tree child order to match managed_cards order.
	# Godot uses tree order as a tiebreaker for Control picking,
	# so this must stay in sync with z_index for correct hover targets.
	for i in range(managed_cards.size()):
		if managed_cards[i].get_index() != i:
			move_child(managed_cards[i], i)

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
		if card.has_signal("card_right_clicked"):
			card.card_right_clicked.connect(_on_card_right_clicked)


func _arrange_hand_arc(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return

	# Clamp arc angle so total width stays within max_width
	var effective_angle = arc_angle
	if max_width > 0 and count > 1:
		# The rightmost card x = sin(half_angle) * arc_radius
		# Total width ≈ 2 * sin(half_angle) * arc_radius + card_width
		var card_width: float = 150.0
		if not managed_cards.is_empty() and managed_cards[0].size.x > 0:
			card_width = managed_cards[0].size.x * managed_cards[0].scale.x
		var available = max_width - card_width
		if available > 0:
			var max_half_angle = rad_to_deg(asin(clampf(available / (2.0 * arc_radius), 0.0, 1.0)))
			effective_angle = minf(arc_angle, max_half_angle * 2.0)

	var angle_step = effective_angle / max(1, count - 1) if count > 1 else 0
	var start_angle = -effective_angle / 2.0

	for i in range(count):
		var card = managed_cards[i]
		var angle = start_angle + (angle_step * i)
		var angle_rad = deg_to_rad(angle)

		# Calculate position on arc
		var x = sin(angle_rad) * arc_radius
		var half_angle = effective_angle / 2.0 if effective_angle > 0 else 1.0
		var y = -cos(angle_rad) * arc_radius + arc_radius - vertical_offset * abs(angle / half_angle)

		var target_pos = Vector2(x, y)
		var target_rotation = 0.0  # Keep cards upright (no rotation)

		_move_card_to_position(card, target_pos, target_rotation, animate, i)


## Compute slot positions for a given count using the current layout mode
func _compute_slot_positions(count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if count == 0:
		return positions
	match layout_mode:
		LayoutMode.HAND_ARC:
			var effective_angle = arc_angle
			if max_width > 0 and count > 1:
				var card_width: float = 150.0
				if not managed_cards.is_empty() and managed_cards[0].size.x > 0:
					card_width = managed_cards[0].size.x * managed_cards[0].scale.x
				var available = max_width - card_width
				if available > 0:
					var max_half_angle = rad_to_deg(asin(clampf(available / (2.0 * arc_radius), 0.0, 1.0)))
					effective_angle = minf(arc_angle, max_half_angle * 2.0)
			var angle_step = effective_angle / max(1, count - 1) if count > 1 else 0
			var start_angle = -effective_angle / 2.0
			for i in range(count):
				var angle = start_angle + (angle_step * i)
				var angle_rad = deg_to_rad(angle)
				var x = sin(angle_rad) * arc_radius
				var half_angle = effective_angle / 2.0 if effective_angle > 0 else 1.0
				var y = -cos(angle_rad) * arc_radius + arc_radius - vertical_offset * abs(angle / half_angle)
				positions.append(Vector2(x, y))
		LayoutMode.HORIZONTAL:
			var effective_spacing = card_spacing
			if max_width > 0 and count > 1:
				var card_width: float = 150.0
				if not managed_cards.is_empty() and managed_cards[0].size.x > 0:
					card_width = managed_cards[0].size.x * managed_cards[0].scale.x
				var max_spacing = (max_width - card_width) / (count - 1)
				effective_spacing = minf(card_spacing, max_spacing)
			var total_width = (count - 1) * effective_spacing
			var start_x = -total_width / 2.0
			for i in range(count):
				positions.append(Vector2(start_x + i * effective_spacing, 0))
		_:
			# Fallback: horizontal with card_spacing
			var total_width = (count - 1) * card_spacing
			var start_x = -total_width / 2.0
			for i in range(count):
				positions.append(Vector2(start_x + i * card_spacing, 0))
	return positions


## Arrange non-dragged cards with a gap at gap_index to preview reorder
func _arrange_with_drag_gap(gap_index: int) -> void:
	var total_count := managed_cards.size()
	if total_count <= 1:
		return

	var positions := _compute_slot_positions(total_count)

	# Assign non-dragged cards to slot positions, skipping the gap
	var slot := 0
	for i in range(total_count):
		var card := managed_cards[i]
		if card == dragged_card:
			continue
		if slot == gap_index:
			slot += 1
		_move_card_to_position(card, positions[slot], 0.0, true, slot)
		slot += 1


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

		_move_card_to_position(card, target_pos, 0.0, animate, i)


func _arrange_stack(animate: bool) -> void:
	for i in range(managed_cards.size()):
		var card = managed_cards[i]
		# Slight offset for stacked appearance
		var target_pos = Vector2(i * 2, i * 2)
		_move_card_to_position(card, target_pos, 0.0, animate, i)


func _arrange_horizontal(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return

	var effective_spacing = card_spacing
	if max_width > 0 and count > 1:
		var card_width: float = 150.0
		if not managed_cards.is_empty() and managed_cards[0].size.x > 0:
			card_width = managed_cards[0].size.x * managed_cards[0].scale.x
		var max_spacing = (max_width - card_width) / (count - 1)
		effective_spacing = minf(card_spacing, max_spacing)

	var total_width = (count - 1) * effective_spacing
	var start_x = -total_width / 2.0

	for i in range(count):
		var card = managed_cards[i]
		var target_pos = Vector2(start_x + i * effective_spacing, 0)
		_move_card_to_position(card, target_pos, 0.0, animate, i)


func _arrange_vertical(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return

	var total_height = (count - 1) * card_spacing
	var start_y = -total_height / 2.0

	for i in range(count):
		var card = managed_cards[i]
		var target_pos = Vector2(0, start_y + i * card_spacing)
		_move_card_to_position(card, target_pos, 0.0, animate, i)


func restore_drop_handled_card_position() -> void:
	## Move the most-recently drop-handled card back to its hand slot without
	## re-arranging the rest of the hand. Used when an external action that
	## consumed a hand card (e.g. monster play) was cancelled, so the card's
	## data is back in the hand but its visual was left at the drop position.
	if not _drop_handled_card or _drop_handled_card not in managed_cards:
		_drop_handled_card = null
		return
	var idx := managed_cards.find(_drop_handled_card)
	var positions := _compute_slot_positions(managed_cards.size())
	if idx >= 0 and idx < positions.size():
		_move_card_to_position(_drop_handled_card, positions[idx], 0.0, true, idx)
	_drop_handled_card = null


func _move_card_to_position(card: Control, target_pos: Vector2, target_rotation: float, animate: bool, target_z: int = -1) -> void:
	# Store the target position and rotation for this card
	card_target_positions[card] = target_pos
	card_target_rotations[card] = target_rotation

	# Set z_index immediately so input routing matches visual stacking order
	# during the animation (not deferred via tween callback)
	if target_z >= 0:
		card.z_index = target_z

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
	_drag_preview_index = -1
	# A new drag invalidates any pending drop-handled restore from a previous drag.
	_drop_handled_card = null
	# Store dragging state
	if card in managed_cards:
		dragged_card = card
		dragged_card_original_index = managed_cards.find(card)
		card.z_index = 100
		hand_card_drag_started.emit(card)


func _on_card_drag_ended(card: Control) -> void:
	if card not in managed_cards:
		return

	_drag_preview_index = -1

	# Let external listeners handle the drop first (e.g. dropping on a zone)
	drop_handled = false
	hand_card_drag_ended.emit(card)
	if drop_handled:
		# External handler accepted the drop and is mid-action. Remember the
		# card so restore_drop_handled_card_position() can put it back if the
		# action gets cancelled (e.g. apply_play_cost declined).
		_drop_handled_card = card
		dragged_card = null
		dragged_card_original_index = -1
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


## Enable selection mode - clicking a card emits card_selected instead of dragging
func enter_selection_mode(valid_indices: Array[int] = []) -> void:
	selection_mode = true
	selectable_indices = valid_indices
	for i in range(managed_cards.size()):
		var card = managed_cards[i]
		var is_valid = valid_indices.is_empty() or i in valid_indices
		if card.has_method("set_face_down"):
			pass  # Don't change face state
		if "is_selectable" in card:
			card.is_selectable = is_valid
		if "drag_enabled" in card:
			card.drag_enabled = false
		if card.has_signal("card_clicked") and not card.card_clicked.is_connected(_on_card_clicked):
			card.card_clicked.connect(_on_card_clicked)


## Disable selection mode - restore normal drag behavior
func exit_selection_mode() -> void:
	selection_mode = false
	selectable_indices = []
	for card in managed_cards:
		if "is_selectable" in card:
			card.is_selectable = false
		if "drag_enabled" in card:
			card.drag_enabled = true
		if card.has_signal("card_clicked") and card.card_clicked.is_connected(_on_card_clicked):
			card.card_clicked.disconnect(_on_card_clicked)


func _on_card_right_clicked(card: Control) -> void:
	hand_card_right_clicked.emit(card)


func _on_card_clicked(card: Control) -> void:
	if not selection_mode:
		return
	var index = managed_cards.find(card)
	if index >= 0:
		card_selected.emit(card, index)
