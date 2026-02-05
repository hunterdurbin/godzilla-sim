extends Node

## Handles drag-and-drop interactions between Cards and Slots
## Add this as a child of your scene to enable card-to-slot dropping

# Keep track of all cards and slots in the scene
var cards: Array[Control] = []
var slots: Array[Control] = []
var dragging_card: Control = null
var card_original_parent: Node = null
var card_original_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Wait a frame for the scene to be fully ready
	await get_tree().process_frame
	_find_and_register_nodes()


## Find all Cards and Slots in the scene tree
func _find_and_register_nodes() -> void:
	_register_nodes_recursive(get_tree().root)
	print("DragDropHandler: Found %d cards and %d slots" % [cards.size(), slots.size()])


func _register_nodes_recursive(node: Node) -> void:
	# Check if this node is a Card
	if node is Control and node.has_signal("drag_started") and node.has_signal("drag_ended"):
		if node not in cards:
			_register_card(node)

	# Check if this node is a Slot
	if node.has_method("try_accept_card") and node.has_method("is_empty"):
		if node not in slots:
			_register_slot(node)

	# Recurse through children
	for child in node.get_children():
		_register_nodes_recursive(child)


func _register_card(card: Control) -> void:
	cards.append(card)
	card.drag_started.connect(_on_card_drag_started.bind(card))
	card.drag_ended.connect(_on_card_drag_ended.bind(card))


func _register_slot(slot: Control) -> void:
	slots.append(slot)


func _on_card_drag_started(card: Control) -> void:
	dragging_card = card
	card_original_parent = card.get_parent()
	card_original_position = card.position

	# Highlight empty slots
	for slot in slots:
		if slot.has_method("is_empty") and slot.is_empty():
			if slot.has_method("set_highlighted"):
				slot.set_highlighted(true)


func _on_card_drag_ended(card: Control) -> void:
	# Un-highlight all slots
	for slot in slots:
		if slot.has_method("set_highlighted"):
			slot.set_highlighted(false)

	# Check if card was dropped over a slot
	var target_slot = _find_slot_under_card(card)

	if target_slot:
		# Try to place card in the slot
		var success = target_slot.try_accept_card(card)
		if success:
			print("Card placed in slot successfully")
		else:
			# Slot rejected the card, return to original position
			_return_card_to_original_position(card)
	else:
		# No slot found, return card to original position
		_return_card_to_original_position(card)

	dragging_card = null


func _find_slot_under_card(card: Control) -> Control:
	"""Find which slot (if any) the card is currently over"""
	var card_center = card.global_position + (card.size * card.scale) / 2.0

	# Check each slot to see if the card center is within its bounds
	for slot in slots:
		var slot_rect = Rect2(slot.global_position, slot.size)
		if slot_rect.has_point(card_center):
			return slot

	return null


func _return_card_to_original_position(card: Control) -> void:
	"""Return card to its original position if drop failed"""
	if card_original_parent and is_instance_valid(card_original_parent):
		# If card was moved out of its parent, move it back
		if card.get_parent() != card_original_parent:
			if card.get_parent():
				card.get_parent().remove_child(card)
			card_original_parent.add_child(card)

		# Animate back to original position
		if card.has_method("return_to_position"):
			card.return_to_position(card_original_position, 0.3)
		else:
			card.position = card_original_position
