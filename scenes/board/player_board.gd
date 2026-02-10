extends Control

## Visual representation of one player's side of the board.
## Uses zones.svg as the background with anchor-based positioning matching the SVG layout.
## The LayoutContainer maintains the SVG's 1728:1008 aspect ratio within the available space.
## Mirroring for Player 2 flips all child anchors and the background texture.

signal zone_card_dropped(zone_index: int, card: Control)
signal discard_clicked(player_id: int)
signal monster_deck_clicked(player_id: int)
signal zone_slot_clicked(zone_number: int, player_id: int)
signal zone_slot_right_clicked(zone_number: int, player_id: int)
signal strategy_slot_right_clicked(strategy_index: int, player_id: int)
signal card_preview_requested(data: Dictionary)
signal card_preview_cleared()

@export var player_id: int = 0
@export var is_mirrored: bool = false  # True for player 2 (top of screen)

var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")

# SVG viewBox dimensions for aspect ratio calculation
const SVG_W := 1728.0
const SVG_H := 1008.0

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
var monster_info_display: Control
var monster_deck_count_label: Label
var player_label: Label
var cp_label: Label
var threat_label: Label


func _ready() -> void:
	clip_contents = true
	_setup_references()
	resized.connect(_update_layout)
	_update_layout()


func _update_layout() -> void:
	# Crop into the zone content area of the SVG, removing empty top/bottom space.
	# Non-mirrored: content at ~0.20-0.95 in SVG space (top is empty).
	# Mirrored: content at ~0.05-0.80 in SVG space (bottom is empty after flip).
	var content_top: float
	var content_bottom: float
	if is_mirrored:
		content_top = 0.03
		content_bottom = 0.82
	else:
		content_top = 0.18
		content_bottom = 0.97

	var content_span := content_bottom - content_top
	var lc_height := size.y / content_span

	var lc := $LayoutContainer
	lc.offset_left = 0
	lc.offset_top = -content_top * lc_height
	lc.offset_right = size.x
	lc.offset_bottom = lc.offset_top + lc_height


func _setup_references() -> void:
	# Mirror for player 2: flip all child anchors and background
	if is_mirrored:
		_apply_mirror()

	# Zone slots (find by name so layout doesn't matter)
	zone_slots.resize(8)

	for i in range(1, 9):
		var slot := find_child("Zone%d" % i, true, false) as Slot
		if slot:
			slot.zone_number = i
			slot.slot_type = "battle_zone"
			slot.player_id = player_id
			slot.slot_clicked.connect(_on_zone_slot_clicked)
			slot.slot_right_clicked.connect(_on_zone_slot_right_clicked)
			slot.slot_hover_preview.connect(_on_slot_hover_preview)
			slot.slot_hover_preview_cleared.connect(_on_slot_hover_cleared)
			zone_slots[i - 1] = slot

	# Strategy slots (landscape orientation)
	for i in range(1, 3):
		var slot := find_child("Strategy%d" % i, true, false) as Slot
		if slot:
			slot.zone_number = 0
			slot.slot_type = "strategy_zone"
			slot.player_id = player_id
			slot.landscape = true
			slot.slot_right_clicked.connect(_on_strategy_slot_right_clicked.bind(i - 1))
			slot.slot_hover_preview.connect(_on_slot_hover_preview)
			slot.slot_hover_preview_cleared.connect(_on_slot_hover_cleared)
			strategy_slots.append(slot)

	# Info nodes
	deck_count_label = find_child("DeckCount", true, false) as Label
	discard_count_label = find_child("DiscardCount", true, false) as Label
	rage_label = find_child("RageLabel", true, false) as Label
	rage_display = find_child("RageDisplay", true, false) as Control
	discard_display = find_child("DiscardInfo", true, false) as Control
	monster_info_display = find_child("MonsterInfo", true, false) as Control
	monster_deck_count_label = find_child("MonsterDeckCount", true, false) as Label
	player_label = find_child("PlayerLabel", true, false) as Label

	cp_label = find_child("CPLabel", true, false) as Label
	threat_label = find_child("ThreatLabel", true, false) as Label

	if player_label:
		player_label.text = "Player %d" % (player_id + 1)

	# Make discard area clickable
	if discard_display:
		discard_display.mouse_filter = Control.MOUSE_FILTER_STOP
		discard_display.gui_input.connect(_on_discard_gui_input)

	# Make monster info area clickable
	if monster_info_display:
		monster_info_display.mouse_filter = Control.MOUSE_FILTER_STOP
		monster_info_display.gui_input.connect(_on_monster_info_gui_input)

	# Add borders to clickable info areas
	var deck_display := find_child("DeckInfo", true, false) as Control
	for area in [deck_display, discard_display, monster_info_display]:
		if area:
			_add_border(area)


## Sync the entire board display to match a PlayerState
func sync_to_state(player_state: PlayerState, cp_modifier: int = 0, threat_modifier: int = 0, zone_cp_mods: Array = []) -> void:
	_sync_zones(player_state, zone_cp_mods)
	_sync_strategy_zones(player_state)
	_sync_monster(player_state, threat_modifier)
	_sync_hand(player_state)
	_sync_info(player_state, cp_modifier, threat_modifier)


func _sync_zones(state: PlayerState, zone_cp_mods: Array = []) -> void:
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
		var zone_data: Dictionary = state.get_zone_top_card(i)
		var stack_size: int = state.get_zone_stack(i).size()
		var cp_mod: int = zone_cp_mods[i] if i < zone_cp_mods.size() else 0

		# Update card in slot
		if zone_data.is_empty() and slot.has_card() and slot.get_card() != monster_card:
			slot.remove_card(true)
		elif not zone_data.is_empty() and not slot.has_card():
			var card := _create_card(zone_data)
			card.drag_enabled = false
			slot.place_card(card, false)
			if stack_size > 1:
				_add_stack_badge(card, stack_size)
			_update_modifier_badge(card, cp_mod)
		elif not zone_data.is_empty() and slot.has_card():
			var card := slot.get_card()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(zone_data)
			_update_stack_badge(card, stack_size)
			_update_modifier_badge(card, cp_mod)


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


func _sync_monster(state: PlayerState, threat_mod: int = 0) -> void:
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

		_update_modifier_badge(monster_card, threat_mod)

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
			if is_mirrored:
				card.invert_hover = true
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


func _sync_info(state: PlayerState, cp_modifier: int = 0, threat_modifier: int = 0) -> void:
	if deck_count_label:
		deck_count_label.text = "%d" % state.main_deck.size()
	if discard_count_label:
		discard_count_label.text = "%d" % state.discard_pile.size()
	if monster_deck_count_label:
		monster_deck_count_label.text = "Deck: %d" % state.monster_deck.size()
	if cp_label:
		var total_cp: int = state.get_total_counter_power() + cp_modifier
		cp_label.text = "%d" % total_cp
	if threat_label:
		var total_threat: int = state.get_threat_level() + threat_modifier
		threat_label.text = "%d" % total_threat


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


func _apply_mirror() -> void:
	var bg := $LayoutContainer/Background as TextureRect
	if bg:
		bg.flip_h = true
		bg.flip_v = true
	for child in $LayoutContainer.get_children():
		if child is TextureRect:
			continue
		if child is Control:
			_flip_node_anchors(child)


func _flip_node_anchors(node: Control) -> void:
	var l := node.anchor_left
	var t := node.anchor_top
	var r := node.anchor_right
	var b := node.anchor_bottom
	# Set the larger values first to avoid clamping
	node.anchor_right = 1.0 - l
	node.anchor_bottom = 1.0 - t
	node.anchor_left = 1.0 - r
	node.anchor_top = 1.0 - b
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0


func toggle_mirrored() -> void:
	is_mirrored = !is_mirrored
	# Flip all child anchors (flipping twice = identity, so this toggles)
	for child in $LayoutContainer.get_children():
		if child is TextureRect:
			continue
		if child is Control:
			_flip_node_anchors(child)
	var bg := $LayoutContainer/Background as TextureRect
	if bg:
		bg.flip_h = is_mirrored
		bg.flip_v = is_mirrored
	# Recalculate LayoutContainer crop for the new mirrored state
	_update_layout()


func _on_discard_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		discard_clicked.emit(player_id)


func _on_monster_info_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		monster_deck_clicked.emit(player_id)


func _on_zone_slot_clicked(zone_num: int, pid: int) -> void:
	zone_slot_clicked.emit(zone_num, pid)


func _on_zone_slot_right_clicked(zone_num: int, pid: int) -> void:
	zone_slot_right_clicked.emit(zone_num, pid)


func _on_strategy_slot_right_clicked(_zone_num: int, _pid: int, strategy_idx: int) -> void:
	strategy_slot_right_clicked.emit(strategy_idx, player_id)


func _create_card(data: Dictionary) -> Control:
	var card: Control = card_scene.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(data)
	if card.has_signal("card_hover_started"):
		card.card_hover_started.connect(_on_card_hover_started)
	if card.has_signal("card_hover_ended"):
		card.card_hover_ended.connect(_on_card_hover_ended)
	return card


func _on_slot_hover_preview(data: Dictionary) -> void:
	card_preview_requested.emit(data)


func _on_slot_hover_cleared() -> void:
	card_preview_cleared.emit()


func _on_card_hover_started(card_ctrl: Control) -> void:
	if "card_data" in card_ctrl and not card_ctrl.card_data.is_empty():
		card_preview_requested.emit(card_ctrl.card_data)


func _on_card_hover_ended(_card_ctrl: Control) -> void:
	card_preview_cleared.emit()


func _add_stack_badge(card: Control, count: int) -> void:
	if count <= 1:
		return
	var badge := Label.new()
	badge.name = "StackBadge"
	badge.text = "x%d" % count
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color.YELLOW)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 3)
	badge.position = Vector2(4, 4)
	card.add_child(badge)


func _update_stack_badge(card: Control, count: int) -> void:
	var badge := card.get_node_or_null("StackBadge")
	if count <= 1:
		if badge:
			badge.queue_free()
	else:
		if not badge:
			_add_stack_badge(card, count)
		else:
			badge.text = "x%d" % count


func _update_modifier_badge(card: Control, modifier: int) -> void:
	var badge := card.get_node_or_null("ModifierBadge")
	if modifier == 0:
		if badge:
			badge.queue_free()
		return
	if not badge:
		badge = Label.new()
		badge.name = "ModifierBadge"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 3)
		badge.anchor_left = 0.4
		badge.anchor_right = 0.95
		badge.anchor_top = 0.72
		badge.anchor_bottom = 0.84
		card.add_child(badge)
	var prefix := "+" if modifier > 0 else ""
	badge.text = "%s%d" % [prefix, modifier]
	badge.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1) if modifier > 0 else Color(1.0, 0.3, 0.3, 1))


func _add_border(control: Control) -> void:
	control.draw.connect(_draw_border.bind(control))
	control.resized.connect(control.queue_redraw)
	control.queue_redraw()


func _draw_border(control: Control) -> void:
	var rect := Rect2(Vector2.ZERO, control.size)
	control.draw_rect(rect, Color(0.45, 0.45, 0.55, 0.9), false, 2.0)
