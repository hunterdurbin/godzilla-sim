extends Control

## Visual representation of one player's side of the board.
## Two-row layout matching the official playmat:
##   Front row: Strategy Zones | Rage Zone | Zone 8 | Zone 7 | Zone 6 | Deck
##   Back row:  Monster Info   | Zone 1 | Zone 2 | Zone 3 | Zone 4 | Zone 5 | Discard
## HandArea (CardManager) is managed by the parent GameBoard, not this scene.

signal zone_card_dropped(zone_index: int, card: Control)
signal discard_clicked(player_id: int)

@export var player_id: int = 0
@export var is_mirrored: bool = false  # True for player 2 (top of screen)
@export var zone_h_gap: float = 4.0
@export var zone_v_gap: float = 4.0

var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")

# Node references (set in _ready)
var zone_slots: Array[Slot] = []
var strategy_slots: Array[Slot] = []
var hand_manager: CardManager  # Set externally by GameBoard
var monster_card: Control
var monster_card_zone: int = -1  # Zone index (0-7) where monster card is currently placed
var deck_count_label: Label
var discard_count_label: Label
var rage_label: Label
var rage_display: Control
var discard_display: Control
var player_label: Label


func _ready() -> void:
	_setup_references()
	_apply_spacing()


func _setup_references() -> void:
	# Mirror for player 2: swap row order AND reverse children within each row
	# This creates a 180° rotated appearance matching the physical playmat
	if is_mirrored:
		var rows := $Rows
		rows.move_child($Rows/BackRow, 0)
		_reverse_container($Rows/FrontRow)
		_reverse_container($Rows/BackRow)
		_reverse_container($Rows/FrontRow/LeftInfo)

	# Zone slots (find by name so layout wrappers don't matter)
	zone_slots.resize(8)

	for i in range(1, 9):
		var slot := find_child("Zone%d" % i, true, false) as Slot
		if slot:
			slot.zone_number = i
			slot.slot_type = "battle_zone"
			slot.player_id = player_id
			zone_slots[i - 1] = slot

	# Strategy slots
	for i in range(1, 3):
		var slot := find_child("Strategy%d" % i, true, false) as Slot
		if slot:
			slot.zone_number = 0
			slot.slot_type = "strategy_zone"
			slot.player_id = player_id
			strategy_slots.append(slot)

	# Info nodes
	deck_count_label = find_child("DeckCount", true, false) as Label
	discard_count_label = find_child("DiscardCount", true, false) as Label
	rage_label = find_child("RageLabel", true, false) as Label
	rage_display = find_child("RageDisplay", true, false) as Control
	discard_display = find_child("DiscardInfo", true, false) as Control
	player_label = find_child("PlayerLabel", true, false) as Label

	if player_label:
		player_label.text = "Player %d" % (player_id + 1)

	# Make discard area clickable
	if discard_display:
		discard_display.mouse_filter = Control.MOUSE_FILTER_STOP
		discard_display.gui_input.connect(_on_discard_gui_input)


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

		# Skip the monster's zone — monster card is managed by _sync_monster
		if (state.monster_zone - 1) == i:
			slot.set_monster_marker(true)
			# Remove any battle card visual so the monster card can be placed by _sync_monster
			if slot.has_card() and slot.get_card() != monster_card:
				slot.remove_card(true)
			continue

		slot.set_monster_marker(false)
		var zone_data: Dictionary = state.zones[i]

		# Update card in slot
		if zone_data.is_empty() and slot.has_card() and slot.get_card() != monster_card:
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
	var m: Dictionary = state.current_monster
	var target_zone: int = state.monster_zone - 1  # 0-indexed

	if not m.is_empty():
		# Create card if it doesn't exist yet
		if not monster_card:
			monster_card = _create_card(m)
			monster_card.drag_enabled = false
		elif monster_card.has_method("set_card_data_dict"):
			monster_card.set_card_data_dict(m)

		# Move to the correct zone slot if zone changed
		if target_zone != monster_card_zone:
			# Remove from old slot
			if monster_card_zone >= 0 and monster_card_zone < zone_slots.size():
				var old_slot := zone_slots[monster_card_zone]
				if old_slot and old_slot.has_card() and old_slot.get_card() == monster_card:
					old_slot.remove_card(false)
			# Place in new slot
			if target_zone >= 0 and target_zone < zone_slots.size():
				var new_slot := zone_slots[target_zone]
				if new_slot:
					new_slot.place_card(monster_card, false)
			monster_card_zone = target_zone

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


func highlight_strategy_zones() -> void:
	for slot in strategy_slots:
		if slot and not slot.has_card():
			slot.set_highlighted(true)


func highlight_rage_zone(highlight: bool) -> void:
	if rage_display:
		if highlight:
			rage_display.modulate = Color(1.2, 1.5, 1.2, 1.0)
		else:
			rage_display.modulate = Color.WHITE


func highlight_discard_zone(highlight: bool) -> void:
	if discard_display:
		if highlight:
			discard_display.modulate = Color(1.2, 1.5, 1.2, 1.0)
		else:
			discard_display.modulate = Color.WHITE


func clear_highlights() -> void:
	for slot in zone_slots:
		if slot:
			slot.set_highlighted(false)
	for slot in strategy_slots:
		if slot:
			slot.set_highlighted(false)
	highlight_rage_zone(false)
	highlight_discard_zone(false)


func _apply_spacing() -> void:
	$Rows.add_theme_constant_override("separation", int(zone_v_gap))
	$Rows/FrontRow.add_theme_constant_override("separation", int(zone_h_gap))
	$Rows/BackRow.add_theme_constant_override("separation", int(zone_h_gap))



func toggle_mirrored() -> void:
	is_mirrored = !is_mirrored
	if is_mirrored:
		$Rows.move_child($Rows/BackRow, 0)
	else:
		$Rows.move_child($Rows/FrontRow, 0)
	_reverse_container($Rows/FrontRow)
	_reverse_container($Rows/BackRow)
	_reverse_container($Rows/FrontRow/LeftInfo)


func _reverse_container(container: Node) -> void:
	var count := container.get_child_count()
	for i in range(count - 1):
		container.move_child(container.get_child(count - 1), i)


func _on_discard_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		discard_clicked.emit(player_id)


func _create_card(data: Dictionary) -> Control:
	var card: Control = card_scene.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(data)
	return card
