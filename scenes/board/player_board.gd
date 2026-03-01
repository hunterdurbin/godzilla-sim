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
@export var is_mirrored: bool = false # True for player 2 (top of screen)

var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")

# SVG viewBox dimensions for aspect ratio calculation
const SVG_W := 1728.0
const SVG_H := 1008.0

# Node references (set in _ready)
var zone_slots: Array[Slot] = []
var strategy_slots: Array[Slot] = []
var hand_manager: CardManager # Set externally by GameBoard
var monster_card: Control
var monster_card_zone: int = -1 # Zone index (0-7) where monster card is currently placed
var rage_label: Label
var rage_threat_label: Label
var rage_display: Control
var discard_display: Control
var monster_info_display: Control
var cp_label: Label
var threat_label: Label

# Card-based info displays
var _deck_display: Control = null
var _deck_card_backs: Array[Control] = []
var _deck_count_badge: Label = null
var _discard_card: Control = null
var _discard_empty_label: Label = null
var _discard_last_id: String = ""  # Track last shown card to avoid redundant updates
var _discard_count_badge: Label = null
var _monster_deck_card_backs: Array[Control] = []
var _monster_deck_count_badge: Label = null

# Card back texture cache (shared across instances)
const _DEFAULT_CARD_BACK_PATH := "res://CardContent/Assets/cardBacks/default.jpeg"
static var _card_back_cache_loaded: bool = false
static var _default_card_back_tex: Texture2D = null
static var _custom_card_back_tex: Texture2D = null  # null = no custom file found


func _ready() -> void:
	clip_contents = true
	_setup_references()
	_apply_custom_playmat()
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

	# Preserve SVG aspect ratio: if the board is wider than the SVG would be
	# at this height, constrain the width and center horizontally.
	var lc_width := lc_height * (SVG_W / SVG_H)
	var actual_width := minf(lc_width, size.x)
	var x_offset := maxf(0.0, (size.x - actual_width) / 2.0)

	var lc := $LayoutContainer
	lc.offset_left = x_offset
	lc.offset_top = - content_top * lc_height
	lc.offset_right = x_offset + actual_width
	lc.offset_bottom = lc.offset_top + lc_height

	# Constrain playmat background and overlay to match the LayoutContainer width
	var board_bg := $BoardBg as TextureRect
	board_bg.anchor_left = 0.0
	board_bg.anchor_right = 0.0
	board_bg.anchor_top = 0.0
	board_bg.anchor_bottom = 1.0
	board_bg.offset_left = x_offset
	board_bg.offset_right = x_offset + actual_width

	var overlay := $GradientOverlay as ColorRect
	overlay.anchor_left = 0.0
	overlay.anchor_right = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_bottom = 1.0
	overlay.offset_left = x_offset
	overlay.offset_right = x_offset + actual_width

	# On mobile, bump label font sizes so they're readable on smaller boards.
	# The LayoutContainer scales via anchors but font sizes are fixed pixels,
	# so we set explicit sizes that work at phone scale.
	if TouchHelper._is_mobile:
		_apply_mobile_labels()


var _mobile_labels_applied := false

# Cached label references for mobile font scaling
var _cp_title: Label
var _threat_title: Label
var _rage_title: Label

func _apply_mobile_labels() -> void:
	if _mobile_labels_applied:
		return
	_mobile_labels_applied = true
	var lc := $LayoutContainer
	# Combine CP and Threat into a single compact line: "CP: 0 | Threat: 5000"
	# by hiding the separate title labels and increasing value font sizes.
	var stats := lc.find_child("StatsDisplay", true, false) as HBoxContainer
	if stats:
		stats.clip_contents = true
	_cp_title = lc.find_child("CPTitle", true, false) as Label
	_threat_title = lc.find_child("ThreatTitle", true, false) as Label
	var spacer := lc.find_child("Spacer", true, false) as Control
	if _threat_title:
		_threat_title.text = "T:"  # Abbreviate to save horizontal space
	if spacer:
		spacer.custom_minimum_size.x = 2.0
	if cp_label:
		cp_label.custom_minimum_size.x = 0.0
		cp_label.clip_text = false
		cp_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if threat_label:
		threat_label.custom_minimum_size.x = 0.0
		threat_label.clip_text = false
		threat_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_rage_title = lc.find_child("RageTitle", true, false) as Label
	# Apply default (balanced) font sizes
	apply_mobile_label_scale(1.0)


## Update mobile label font sizes based on board scale.
## scale = 1.0 for balanced/enlarged, ~0.6 for shrunk board.
func apply_mobile_label_scale(label_scale: float) -> void:
	var title_size := maxi(10, int(12 * label_scale))
	var value_size := maxi(10, int(14 * label_scale))
	var rage_size := maxi(14, int(28 * label_scale))
	var rage_threat_size := maxi(10, int(18 * label_scale))
	if _cp_title:
		_cp_title.add_theme_font_size_override("font_size", title_size)
	if _threat_title:
		_threat_title.add_theme_font_size_override("font_size", title_size)
	if cp_label:
		cp_label.add_theme_font_size_override("font_size", value_size)
	if threat_label:
		threat_label.add_theme_font_size_override("font_size", value_size)
	if _rage_title:
		_rage_title.add_theme_font_size_override("font_size", title_size)
	if rage_label:
		rage_label.add_theme_font_size_override("font_size", rage_size)
	if rage_threat_label:
		rage_threat_label.add_theme_font_size_override("font_size", rage_threat_size)


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
	for i in range(1, 4):
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
	rage_label = find_child("RageLabel", true, false) as Label
	rage_threat_label = find_child("RageThreatLabel", true, false) as Label
	rage_display = find_child("RageDisplay", true, false) as Control
	_style_rage_bg()
	_deck_display = find_child("DeckInfo", true, false) as Control
	discard_display = find_child("DiscardInfo", true, false) as Control
	monster_info_display = find_child("MonsterInfo", true, false) as Control

	cp_label = find_child("CPLabel", true, false) as Label
	threat_label = find_child("ThreatLabel", true, false) as Label

	# Deck: dynamic stack of face-down cards (height reflects card count) + hover count badge
	if _deck_display:
		_create_deck_stack(_deck_display, _deck_card_backs)
		_deck_count_badge = _create_count_badge()
		_deck_display.add_child(_deck_count_badge)
		_deck_display.mouse_entered.connect(_deck_count_badge.show)
		_deck_display.mouse_exited.connect(_deck_count_badge.hide)

	# Discard: face-up top card + empty placeholder + hover count badge
	if discard_display:
		_discard_empty_label = Label.new()
		_discard_empty_label.text = "Discard"
		_discard_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_discard_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_discard_empty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_discard_empty_label.add_theme_font_size_override("font_size", 9)
		_discard_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		discard_display.add_child(_discard_empty_label)

		_discard_card = _create_card({})
		_discard_card.drag_enabled = false
		_discard_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_discard_card.custom_minimum_size = Vector2.ZERO
		_discard_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_discard_card.visible = false
		discard_display.add_child(_discard_card)
		# Also ignore mouse on the card's background panel
		var bg := _discard_card.get_node_or_null("Background") as Control
		if bg:
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_discard_count_badge = _create_count_badge()
		discard_display.add_child(_discard_count_badge)

	# Monster deck: dynamic stack of face-down cards + hover count badge + player label
	if monster_info_display:
		_create_deck_stack(monster_info_display, _monster_deck_card_backs)
		_monster_deck_count_badge = _create_count_badge()
		monster_info_display.add_child(_monster_deck_count_badge)
		monster_info_display.mouse_entered.connect(_monster_deck_count_badge.show)
		monster_info_display.mouse_exited.connect(_monster_deck_count_badge.hide)

	# Make discard area clickable + hover preview/badge
	if discard_display:
		discard_display.mouse_filter = Control.MOUSE_FILTER_STOP
		discard_display.gui_input.connect(_on_discard_gui_input)
		discard_display.mouse_entered.connect(_on_discard_hover_started)
		discard_display.mouse_exited.connect(_on_discard_hover_ended)

	# Make monster info area clickable
	if monster_info_display:
		monster_info_display.mouse_filter = Control.MOUSE_FILTER_STOP
		monster_info_display.gui_input.connect(_on_monster_info_gui_input)

	# Add borders to info areas
	for area in [_deck_display, discard_display, monster_info_display]:
		if area:
			_add_border(area)


func _apply_custom_playmat() -> void:
	if not GameSettings.custom_playmat_enabled:
		return
	var local_id := NetworkManager.get_local_player_id() if NetworkManager.is_multiplayer() else 0
	if player_id != local_id and not GameSettings.custom_playmat_opponent:
		return
	var dir_path := GameSettings.get_custom_base_path().path_join("playmat")
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var image_path := dir_path.path_join("default.%s" % ext)
		if FileAccess.file_exists(image_path):
			var image := Image.load_from_file(image_path)
			if image:
				var tex := ImageTexture.create_from_image(image)
				var board_bg := $BoardBg as TextureRect
				if board_bg:
					board_bg.texture = tex
			return


## Apply a gradient tint to the board background based on the rank 1 monster's colors.
## Call once during initial board setup.
func apply_monster_gradient(monster_data: Dictionary) -> void:
	if GameSettings.color_overlay_mode == 0:
		return
	var local_id := NetworkManager.get_local_player_id() if NetworkManager.is_multiplayer() else 0
	var is_self := player_id == local_id
	if is_self and GameSettings.color_overlay_mode == 2:
		return
	if not is_self and GameSettings.color_overlay_mode == 1:
		return
	var overlay := $GradientOverlay as ColorRect
	if not overlay:
		return
	var colors: Array = monster_data.get("colors", [])
	if colors.is_empty():
		return
	var gradient := GradientTexture2D.new()
	var grad := Gradient.new()
	if colors.size() == 1:
		var c: Color = CardEnums.color_to_godot_color(colors[0])
		c.a = 0.15
		grad.colors = PackedColorArray([c, Color(c.r, c.g, c.b, 0.0)])
	else:
		var c1: Color = CardEnums.color_to_godot_color(colors[0])
		var c2: Color = CardEnums.color_to_godot_color(colors[1])
		c1.a = 0.15
		c2.a = 0.15
		grad.colors = PackedColorArray([c1, c2])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.gradient = grad
	gradient.width = 256
	gradient.height = 256
	gradient.fill_from = Vector2(0.0, 0.0)
	gradient.fill_to = Vector2(1.0, 1.0)
	# Use a TextureRect instead of ColorRect for gradient support
	var tex_rect := TextureRect.new()
	tex_rect.texture = gradient
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(tex_rect)
	overlay.color = Color(0, 0, 0, 0) # Keep parent transparent


## Sync the entire board display to match a PlayerState
func sync_to_state(player_state: PlayerState, cp_modifier: int = 0, threat_modifier: int = 0, zone_cp_mods: Array = [], strategy_cp_mods: Array = [], zone_rank_mods: Array = []) -> void:
	_sync_zones(player_state, zone_cp_mods, zone_rank_mods)
	_sync_strategy_zones(player_state, strategy_cp_mods)
	_sync_monster(player_state, threat_modifier)
	_sync_hand(player_state)
	_sync_info(player_state, cp_modifier, threat_modifier)


func _sync_zones(state: PlayerState, zone_cp_mods: Array = [], zone_rank_mods: Array = []) -> void:
	for i in range(mini(zone_slots.size(), 8)):
		var slot := zone_slots[i]
		if not slot:
			continue

		# Skip the monster's zone — monster card is managed by _sync_monster
		# Clamp to zone 8 (index 7) so victory invasion still shows monster
		if mini(state.monster_zone - 1, zone_slots.size() - 1) == i:
			slot.set_monster_marker(true)
			# Remove any battle card visual so the monster card can be placed by _sync_monster
			if slot.has_card() and slot.get_card() != monster_card:
				slot.remove_card(true)
			continue

		slot.set_monster_marker(false)
		var zone_data: Dictionary = state.get_zone_top_card(i)
		var stack_size: int = state.get_zone_stack(i).size()
		var cp_mod: int = zone_cp_mods[i] if i < zone_cp_mods.size() else 0
		var rank_mod: int = zone_rank_mods[i] if i < zone_rank_mods.size() else 0

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
			_update_rank_modifier_badge(card, rank_mod)
		elif not zone_data.is_empty() and slot.has_card():
			var card := slot.get_card()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(zone_data)
			_update_stack_badge(card, stack_size)
			_update_modifier_badge(card, cp_mod)
			_update_rank_modifier_badge(card, rank_mod)


func _sync_strategy_zones(state: PlayerState, strategy_cp_mods: Array = []) -> void:
	var zone_count: int = state.strategy_zones.size()

	# Show/hide and reposition slots when 3rd strategy zone is added
	if zone_count >= 3 and strategy_slots.size() >= 3 and not strategy_slots[2].visible:
		_redistribute_strategy_slots(zone_count)

	for i in range(mini(strategy_slots.size(), zone_count)):
		var slot := strategy_slots[i]
		if not slot:
			continue
		var sz_data: Dictionary = state.strategy_zones[i]
		var cp_mod: int = strategy_cp_mods[i] if i < strategy_cp_mods.size() else 0

		if sz_data.is_empty() and slot.has_card():
			slot.remove_card(true)
		elif not sz_data.is_empty() and not slot.has_card():
			var card := _create_card(sz_data)
			card.drag_enabled = false
			slot.place_card(card, false)
			_update_strategy_modifier_badge(card, cp_mod)
		elif not sz_data.is_empty() and slot.has_card():
			_update_strategy_modifier_badge(slot.get_card(), cp_mod)


func _redistribute_strategy_slots(count: int) -> void:
	if count < 3 or strategy_slots.size() < 3:
		return
	# Redistribute 3 strategy slots within the original 2-slot vertical space
	var top_start := 0.204
	var bottom_end := 0.5969
	var gap := 0.01
	var zone_height := (bottom_end - top_start - gap * (count - 1)) / count
	for i in range(count):
		var slot := strategy_slots[i]
		var a_top := top_start + i * (zone_height + gap)
		var a_bottom := a_top + zone_height
		if is_mirrored:
			var flipped_top := 1.0 - a_bottom
			var flipped_bottom := 1.0 - a_top
			a_top = flipped_top
			a_bottom = flipped_bottom
		slot.custom_minimum_size = Vector2.ZERO
		# Set larger anchor first to avoid clamping
		slot.anchor_bottom = a_bottom
		slot.anchor_top = a_top
		slot.offset_top = 0
		slot.offset_bottom = 0
		slot.visible = true


func _sync_monster(state: PlayerState, threat_mod: int = 0) -> void:
	var m: Dictionary = state.current_monster
	var target_zone: int = mini(state.monster_zone - 1, zone_slots.size() - 1) # 0-indexed, clamped to zone 8

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
	if rage_threat_label:
		var threat_bonus: int = state.rage * 5000
		rage_threat_label.text = "(+%d)" % threat_bonus


func _sync_hand(state: PlayerState) -> void:
	if not hand_manager:
		return

	var current_cards := hand_manager.get_cards()

	# Same set of cards (ignoring visual order) — nothing to do
	if _hand_set_matches(current_cards, state.hand):
		return

	# Diff: match visual cards against state cards by ID (handling duplicates)
	var state_pool: Array[Dictionary] = state.hand.duplicate()
	var cards_to_remove: Array[Control] = []

	for card in current_cards:
		var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
		var found_idx := -1
		for j in range(state_pool.size()):
			if state_pool[j].get("id", "") == card_id:
				found_idx = j
				break
		if found_idx >= 0:
			state_pool.remove_at(found_idx)
		else:
			cards_to_remove.append(card)

	# Suppress intermediate rearrangements
	var was_auto := hand_manager.auto_arrange
	hand_manager.auto_arrange = false

	for card in cards_to_remove:
		hand_manager.remove_card(card, false)
		card.queue_free()

	# state_pool now contains only newly drawn cards
	var new_card_count := state_pool.size()
	for card_data in state_pool:
		var card := _create_card(card_data)
		if is_mirrored:
			card.invert_hover = true
		hand_manager.add_card(card, false)

	# Pre-position new cards at their target slots so they appear at the end
	# instead of flying in from (0,0)
	if new_card_count > 0:
		var total := hand_manager.get_card_count()
		var positions := hand_manager._compute_slot_positions(total)
		var cards := hand_manager.get_cards()
		for k in range(new_card_count):
			var idx := total - new_card_count + k
			if idx >= 0 and idx < positions.size():
				cards[idx].position = positions[idx]

	hand_manager.auto_arrange = was_auto
	hand_manager.arrange_cards(true)


func _hand_set_matches(visual_cards: Array[Control], state_hand: Array) -> bool:
	if visual_cards.size() != state_hand.size():
		return false
	var visual_counts := {}
	for card in visual_cards:
		var id: String = card.card_data.get("id", "") if "card_data" in card else ""
		visual_counts[id] = visual_counts.get(id, 0) + 1
	var state_counts := {}
	for cd in state_hand:
		var id: String = cd.get("id", "")
		state_counts[id] = state_counts.get(id, 0) + 1
	return visual_counts == state_counts


func _sync_info(state: PlayerState, cp_modifier: int = 0, threat_modifier: int = 0) -> void:
	# Deck: show/hide card backs proportional to remaining cards
	var deck_size: int = state.main_deck.size()
	if _deck_count_badge:
		_deck_count_badge.text = "%d" % deck_size
	var visible_count: int = mini(deck_size, _deck_card_backs.size())
	for i in range(_deck_card_backs.size()):
		_deck_card_backs[i].visible = i < visible_count

	# Discard: show top card face-up, update count badge
	var discard_size: int = state.discard_pile.size()
	if _discard_count_badge:
		_discard_count_badge.text = "%d" % discard_size
	if discard_size > 0:
		var top_card: Dictionary = state.discard_pile.back()
		var top_id: String = top_card.get("id", "")
		if _discard_card:
			if top_id != _discard_last_id:
				_discard_card.set_card_data_dict(top_card)
				_discard_last_id = top_id
			_discard_card.visible = true
		if _discard_empty_label:
			_discard_empty_label.visible = false
	else:
		if _discard_card:
			_discard_card.visible = false
			_discard_last_id = ""
		if _discard_empty_label:
			_discard_empty_label.visible = true

	# Monster deck: show/hide card backs proportional to remaining cards
	var monster_deck_size: int = state.monster_deck.size()
	if _monster_deck_count_badge:
		_monster_deck_count_badge.text = "%d" % monster_deck_size
	var monster_visible: int = mini(monster_deck_size, _monster_deck_card_backs.size())
	for i in range(_monster_deck_card_backs.size()):
		_monster_deck_card_backs[i].visible = i < monster_visible

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


func _style_rage_bg() -> void:
	var rage_bg := find_child("RageBg", true, false) as Panel
	if rage_bg:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.3, 0.0)
		style.border_color = Color(1, 1, 1, 0.0)
		style.set_border_width_all(0)
		style.set_corner_radius_all(0)
		rage_bg.add_theme_stylebox_override("panel", style)


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


## Clear all visual state for a fresh game (called during rematch).
func reset_visuals() -> void:
	# Remove all cards from zone slots
	for slot in zone_slots:
		if slot:
			if slot.has_card() and slot.get_card() != monster_card:
				slot.remove_card(true)
			slot.set_highlighted(false)
			slot.set_monster_marker(false)

	# Remove monster card
	if monster_card:
		# Remove from its slot first
		if monster_card_zone >= 0 and monster_card_zone < zone_slots.size():
			var slot := zone_slots[monster_card_zone]
			if slot and slot.has_card() and slot.get_card() == monster_card:
				slot.remove_card(false)
		monster_card.queue_free()
		monster_card = null
	monster_card_zone = -1

	# Remove all cards from strategy slots
	for slot in strategy_slots:
		if slot:
			if slot.has_card():
				slot.remove_card(true)
			slot.set_highlighted(false)

	# Hide 3rd strategy slot if it was made visible (EBP03-013)
	if strategy_slots.size() >= 3:
		strategy_slots[2].visible = false

	# Clear gradient overlay children (TextureRects created by apply_monster_gradient)
	var overlay := $GradientOverlay as ColorRect
	if overlay:
		for child in overlay.get_children():
			child.queue_free()
		overlay.color = Color(0, 0, 0, 0)

	# Reset discard card display
	if _discard_card:
		_discard_card.visible = false
		_discard_last_id = ""
	if _discard_empty_label:
		_discard_empty_label.visible = true

	highlight_rage_zone(false)
	highlight_discard_zone(false)


func _apply_mirror() -> void:
	var bg := $LayoutContainer/Background as TextureRect
	if bg:
		bg.flip_h = true
		bg.flip_v = true
	var board_bg := $BoardBg as TextureRect
	if board_bg:
		board_bg.flip_h = true
		board_bg.flip_v = true
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
	var board_bg := $BoardBg as TextureRect
	if board_bg:
		board_bg.flip_h = is_mirrored
		board_bg.flip_v = is_mirrored
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
	card.owner_player_id = player_id
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
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -40
	badge.offset_right = -4
	badge.offset_top = 4
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


func _update_strategy_modifier_badge(card: Control, modifier: int) -> void:
	var badge := card.get_node_or_null("ModifierBadge")
	if modifier == 0:
		if badge:
			badge.queue_free()
		return
	if not badge:
		badge = Label.new()
		badge.name = "ModifierBadge"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 3)
		card.add_child(badge)
	# Card is portrait in local space; slot rotates -90° CCW for landscape display.
	# Portrait bottom-center → visual middle-right of landscape.
	# Counter-rotate badge +90° so text reads horizontally on screen.
	var bw: float = card.size.x * 0.8
	var bh: float = card.size.y * 0.15
	badge.size = Vector2(bw, bh)
	badge.pivot_offset = Vector2(bw / 2.0, bh / 2.0)
	badge.rotation = deg_to_rad(90)
	badge.position = Vector2(card.size.x * 0.5 - bw / 2.0, card.size.y * 0.75 - bh / 2.0)
	var prefix := "+" if modifier > 0 else ""
	badge.text = "%s%d" % [prefix, modifier]
	badge.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1) if modifier > 0 else Color(1.0, 0.3, 0.3, 1))


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


func _update_rank_modifier_badge(card: Control, modifier: int) -> void:
	var badge := card.get_node_or_null("RankModifierBadge")
	if modifier == 0:
		if badge:
			badge.queue_free()
		return
	if not badge:
		badge = Label.new()
		badge.name = "RankModifierBadge"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 3)
		badge.anchor_left = 0.05
		badge.anchor_right = 0.5
		badge.anchor_top = 0.04
		badge.anchor_bottom = 0.16
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


# --- Card-back stack helpers ---

func _get_card_back_texture() -> Texture2D:
	if not _card_back_cache_loaded:
		_card_back_cache_loaded = true
		_default_card_back_tex = load(_DEFAULT_CARD_BACK_PATH)
		var cb_dir := GameSettings.get_custom_base_path().path_join("cardBack")
		for ext in ["png", "jpg", "jpeg", "webp"]:
			var custom_path := cb_dir.path_join("default.%s" % ext)
			if FileAccess.file_exists(custom_path):
				var image := Image.load_from_file(custom_path)
				if image:
					_custom_card_back_tex = ImageTexture.create_from_image(image)
				break
	if _custom_card_back_tex and _should_use_custom_back():
		return _custom_card_back_tex
	return _default_card_back_tex


func _should_use_custom_back() -> bool:
	var mode: int = GameSettings.custom_card_back_mode
	if mode == 0:
		return false
	if mode == 2:
		return true
	# Mode 1: myself only
	var local_id := NetworkManager.get_local_player_id() if NetworkManager.is_multiplayer() else 0
	return player_id == local_id


func _create_card_back_panel() -> Panel:
	var panel := Panel.new()
	panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.24, 1)
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.4, 0.5, 1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex_rect := TextureRect.new()
	tex_rect.texture = _get_card_back_texture()
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tex_rect)

	return panel


func _create_deck_stack(parent: Control, stack_arr: Array[Control], max_layers: int = 20) -> void:
	## Create a stack of card-back panels that grows/shrinks with deck size.
	## Each layer pushes the card on top up by 1px from the bottom.
	for i in range(max_layers):
		var panel := _create_card_back_panel()
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var shift := float(i)  # 1px per layer, upward from bottom
		panel.offset_top = -shift
		panel.offset_bottom = -shift
		panel.visible = false
		parent.add_child(panel)
		stack_arr.append(panel)


func _on_discard_hover_started() -> void:
	if _discard_count_badge:
		_discard_count_badge.show()
	if _discard_card and _discard_card.visible and not _discard_card.card_data.is_empty():
		card_preview_requested.emit(_discard_card.card_data)


func _on_discard_hover_ended() -> void:
	if _discard_count_badge:
		_discard_count_badge.hide()
	card_preview_cleared.emit()


func _create_count_badge() -> Label:
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	badge.add_theme_constant_override("outline_size", 4)
	badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	badge.offset_top = -24
	badge.offset_bottom = 0
	badge.offset_left = -20
	badge.offset_right = 20
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	return badge
