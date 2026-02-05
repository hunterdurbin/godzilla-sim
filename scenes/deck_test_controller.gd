extends Node2D

## Controller script for DeckTest scene - handles UI and input

@onready var deck: Deck = $Deck
@onready var hand: CardManager = $Hand
@onready var info_label: Label = $UI/InfoLabel
@onready var draw_button: Button = $UI/DrawButton
@onready var draw3_button: Button = $UI/Draw3Button
@onready var shuffle_button: Button = $UI/ShuffleButton


func _ready() -> void:
	# Connect button signals
	draw_button.pressed.connect(_on_draw_button_pressed)
	draw3_button.pressed.connect(_on_draw3_button_pressed)
	shuffle_button.pressed.connect(_on_shuffle_button_pressed)

	# Connect deck signals
	deck.card_drawn.connect(_on_card_drawn)
	deck.deck_shuffled.connect(_on_deck_shuffled)
	deck.deck_empty.connect(_on_deck_empty)

	# Update info
	_update_info()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):  # Space/Enter
		_on_draw_button_pressed()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_D:
				_on_draw_button_pressed()
			KEY_3:
				_on_draw3_button_pressed()
			KEY_S:
				_on_shuffle_button_pressed()


func _on_draw_button_pressed() -> void:
	deck.draw_card(true)


func _on_draw3_button_pressed() -> void:
	deck.draw_cards(3, true)


func _on_shuffle_button_pressed() -> void:
	deck.shuffle()
	_update_info()


func _on_card_drawn(_card: Control) -> void:
	_update_info()


func _on_deck_shuffled() -> void:
	print("Deck shuffled!")


func _on_deck_empty() -> void:
	print("Deck is empty!")
	_update_info()


func _update_info() -> void:
	var deck_count = deck.get_remaining_cards()
	var hand_count = hand.get_card_count()
	var discard_count = deck.get_discard_count()

	info_label.text = "Cards in Deck: %d\nCards in Hand: %d\nDiscard Pile: %d\n\nPress D to draw, 3 to draw 3, S to shuffle" % [deck_count, hand_count, discard_count]
