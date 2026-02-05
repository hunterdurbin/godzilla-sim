extends Control

## Visual representation of one player's side of the board.
## Two-row layout matching the official playmat:
##   Front row: Strategy Zones | Rage Zone | Zone 8 | Zone 7 | Zone 6 | Deck
##   Back row:  Monster Info   | Zone 1 | Zone 2 | Zone 3 | Zone 4 | Zone 5 | Discard
## HandArea (CardManager) is managed by the parent GameBoard, not this scene.

signal zone_card_dropped(zone_index: int, card: Control)

@export var player_id: int = 0
@export var is_mirrored: bool = false  # True for player 2 (top of screen)

var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")

# Node references (set in _ready)
var zone_slots: Array[Slot] = []
var strategy_slots: Array[Slot] = []
var hand_manager: CardManager  # Set externally by GameBoard
var monster_display: Label
var deck_count_label: Label
var discard_count_label: Label
var rage_label: Label
var player_label: Label


func _ready() -> void:
	_setup_references()


func _setup_references() -> void:
	# Mirror row order for player 2: back row on top, front row on bottom
	# so front row faces toward the center of the board
	if is_mirrored:
		var rows := $Rows
		rows.move_child($Rows/BackRow, 0)

	# Zone slots across two rows
	zone_slots.resize(8)

	# Back row: zones 1-5
	for i in range(1, 6):
		var slot := get_node_or_null("Rows/BackRow/Zone%d" % i) as Slot
		if slot:
			slot.zone_number = i
			slot.slot_type = "battle_zone"
			slot.player_id = player_id
			zone_slots[i - 1] = slot

	# Front row: zones 6-8
	for i in range(6, 9):
		var slot := get_node_or_null("Rows/FrontRow/Zone%d" % i) as Slot
		if slot:
			slot.zone_number = i
			slot.slot_type = "battle_zone"
			slot.player_id = player_id
			zone_slots[i - 1] = slot

	# Strategy slots
	for i in range(1, 3):
		var slot := get_node_or_null("Rows/FrontRow/StrategyArea/Strategy%d" % i) as Slot
		if slot:
			slot.zone_number = 0
			slot.slot_type = "strategy_zone"
			slot.player_id = player_id
			strategy_slots.append(slot)

	# Info nodes
	monster_display = get_node_or_null("Rows/BackRow/MonsterInfo/MonsterDisplay") as Label
	deck_count_label = get_node_or_null("Rows/FrontRow/DeckInfo/DeckCount") as Label
	discard_count_label = get_node_or_null("Rows/BackRow/DiscardInfo/DiscardCount") as Label
	rage_label = get_node_or_null("Rows/FrontRow/RageDisplay/RageLabel") as Label
	player_label = get_node_or_null("Rows/BackRow/MonsterInfo/PlayerLabel") as Label

	if player_label:
		player_label.text = "Player %d" % (player_id + 1)


## Sync the entire board display to match a PlayerState
func sync_to_state(player_state: PlayerState) -> void:
	_sync_zones(player_state)
	_sync_strategy_zones(player_state)
	_sync_monster(player_state)
	_sync_hand(player_state)
	_sync_info(player_state)


func _sync_zones(state: PlayerState) -> void:
	for i in range(mini(zone_slots.size(), 8)):
		var slot := zone_slots[i]
		if not slot:
			continue
		var zone_data: Dictionary = state.zones[i]

		# Update monster marker
		slot.set_monster_marker((state.monster_zone - 1) == i)

		# Update card in slot
		if zone_data.is_empty() and slot.has_card():
			slot.remove_card(true)
		elif not zone_data.is_empty() and not slot.has_card():
			var card := _create_card(zone_data)
			card.drag_enabled = false
			slot.place_card(card, false)
		elif not zone_data.is_empty() and slot.has_card():
			var card := slot.get_card()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(zone_data)


func _sync_strategy_zones(state: PlayerState) -> void:
	for i in range(mini(strategy_slots.size(), 2)):
		var slot := strategy_slots[i]
		if not slot:
			continue
		var sz_data: Dictionary = state.strategy_zones[i]

		if sz_data.is_empty() and slot.has_card():
			slot.remove_card(true)
		elif not sz_data.is_empty() and not slot.has_card():
			var card := _create_card(sz_data)
			card.drag_enabled = false
			slot.place_card(card, false)


func _sync_monster(state: PlayerState) -> void:
	if monster_display:
		var m: Dictionary = state.current_monster
		var threat: int = state.get_threat_level()
		var rank_str: String = CardEnums.rank_to_roman(m.get("rank", 1))
		monster_display.text = "%s [%s]\nTL: %d  Zone: %d" % [
			m.get("name", "???"), rank_str, threat, state.monster_zone
		]

	if rage_label:
		rage_label.text = "%d" % state.rage


func _sync_hand(state: PlayerState) -> void:
	if not hand_manager:
		return

	var current_count: int = hand_manager.get_card_count()
	var target_count: int = state.hand.size()

	if current_count != target_count or _hand_data_mismatch(state):
		hand_manager.clear_cards(true)
		for card_data in state.hand:
			var card := _create_card(card_data)
			hand_manager.add_card(card, false)
		hand_manager.arrange_cards(true)


func _hand_data_mismatch(state: PlayerState) -> bool:
	if not hand_manager:
		return false
	var cards := hand_manager.get_cards()
	if cards.size() != state.hand.size():
		return true
	for i in range(cards.size()):
		if "card_data" in cards[i]:
			if cards[i].card_data.get("id") != state.hand[i].get("id"):
				return true
	return false


func _sync_info(state: PlayerState) -> void:
	if deck_count_label:
		deck_count_label.text = "%d" % state.main_deck.size()
	if discard_count_label:
		discard_count_label.text = "%d" % state.discard_pile.size()


func set_hand_face_down(face_down: bool) -> void:
	if not hand_manager:
		return
	for card in hand_manager.get_cards():
		if card.has_method("set_face_down"):
			card.set_face_down(face_down)


func highlight_valid_zones(valid_zone_indices: Array[int]) -> void:
	for i in range(zone_slots.size()):
		if zone_slots[i]:
			zone_slots[i].set_highlighted(i in valid_zone_indices)


func clear_highlights() -> void:
	for slot in zone_slots:
		if slot:
			slot.set_highlighted(false)
	for slot in strategy_slots:
		if slot:
			slot.set_highlighted(false)


func _create_card(data: Dictionary) -> Control:
	var card: Control = card_scene.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(data)
	return card
