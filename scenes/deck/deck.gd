extends Node2D
class_name Deck

## Manages a deck of cards and can draw cards to a connected CardManager (Hand)

# Signals
signal card_drawn(card: Control)
signal deck_shuffled()
signal deck_empty()

# Card scene to instantiate
@export var card_scene: PackedScene

# Connected CardManager (e.g., Player's Hand)
@export var hand_manager: CardManager

# Deck settings
@export var auto_shuffle_on_empty: bool = true
@export var draw_animation_delay: float = 0.1

# Internal state
var deck_data: Array[Dictionary] = []
var discard_pile: Array[Dictionary] = []


func _ready() -> void:
	# Initialize with some test cards if empty
	if deck_data.is_empty():
		_create_test_deck()

	# Update visual card count
	_update_card_count_label()


## Draw a card from the deck and add it to the connected hand manager
func draw_card(animate: bool = true) -> Control:
	if deck_data.is_empty():
		deck_empty.emit()

		if auto_shuffle_on_empty and not discard_pile.is_empty():
			reshuffle_discard()
		else:
			push_warning("Deck: Cannot draw card, deck is empty")
			return null

	if not hand_manager:
		push_error("Deck: No hand_manager connected")
		return null

	if hand_manager.is_full():
		push_warning("Deck: Hand is full, cannot draw card")
		return null

	# Get card data from top of deck
	var card_data = deck_data.pop_front()

	# Create card instance
	var card = _create_card_from_data(card_data)
	if not card:
		return null

	# Position card at deck location initially
	card.global_position = global_position
	card.scale = Vector2.ZERO  # Start small for animation

	# Add to hand manager
	hand_manager.add_card(card, animate)

	# Emit signal
	card_drawn.emit(card)

	# Update visual card count
	_update_card_count_label()

	return card


## Draw multiple cards
func draw_cards(count: int, animate: bool = true) -> Array[Control]:
	var drawn_cards: Array[Control] = []

	for i in range(count):
		var card = draw_card(animate)
		if card:
			drawn_cards.append(card)
			# Add delay between draws for visual effect
			if animate and draw_animation_delay > 0 and i < count - 1:
				await get_tree().create_timer(draw_animation_delay).timeout
		else:
			break  # Stop if we can't draw more

	return drawn_cards


## Shuffle the deck
func shuffle() -> void:
	deck_data.shuffle()
	deck_shuffled.emit()


## Add a card to the discard pile
func discard_card(card_data: Dictionary) -> void:
	discard_pile.append(card_data)


## Reshuffle discard pile back into deck
func reshuffle_discard() -> void:
	deck_data.append_array(discard_pile)
	discard_pile.clear()
	shuffle()


## Get remaining card count
func get_remaining_cards() -> int:
	return deck_data.size()


## Get discard pile count
func get_discard_count() -> int:
	return discard_pile.size()


## Check if deck is empty
func is_empty() -> bool:
	return deck_data.is_empty()


## Add a card to the deck
func add_card_to_deck(card_data: Dictionary, shuffle_after: bool = false) -> void:
	deck_data.append(card_data)
	if shuffle_after:
		shuffle()


## Clear the deck
func clear_deck() -> void:
	deck_data.clear()
	discard_pile.clear()


## Load a deck from an array of card data
func load_deck(cards: Array[Dictionary], should_shuffle: bool = true) -> void:
	deck_data = cards.duplicate()
	discard_pile.clear()
	if should_shuffle:
		shuffle()


## Private methods

func _create_card_from_data(card_data: Dictionary) -> Control:
	"""Create a Card instance from card data"""
	if not card_scene:
		push_error("Deck: card_scene not set")
		return null

	var card = card_scene.instantiate() as Control
	if not card:
		push_error("Deck: Failed to instantiate card")
		return null

	# Set card data (prefer dict-based method for TCG cards)
	if card.has_method("set_card_data_dict") and card_data.has("card_type"):
		card.set_card_data_dict(card_data)
	elif card.has_method("set_card_data"):
		var title = card_data.get("name", "Unknown Card")
		var description = card_data.get("description", "")
		card.set_card_data(title, description)

	return card


func _create_test_deck() -> void:
	"""Create a test deck with sample cards"""
	var test_cards: Array[Dictionary] = [
		{"name": "Fireball", "description": "Deal 3 damage to target"},
		{"name": "Shield", "description": "Block 5 damage"},
		{"name": "Heal", "description": "Restore 4 health"},
		{"name": "Lightning", "description": "Deal 4 damage to all enemies"},
		{"name": "Poison", "description": "Deal 1 damage each turn for 3 turns"},
		{"name": "Armor Up", "description": "Gain 3 armor"},
		{"name": "Draw", "description": "Draw 2 cards"},
		{"name": "Strike", "description": "Deal 2 damage"},
		{"name": "Defend", "description": "Gain 2 block"},
		{"name": "Power Up", "description": "Increase attack by 2"},
	]

	load_deck(test_cards, true)


func _update_card_count_label() -> void:
	"""Update the visual card count display"""
	if has_node("CardCountLabel"):
		$CardCountLabel.text = str(deck_data.size())
