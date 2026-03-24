class_name VRPlayerBoard3D
extends Node3D

## 3D representation of one player's side of the board on the VR table.
## Implements sync_to_state() with the same signature as the 2D PlayerBoard
## so the same logic layer drives both presentations.

signal zone_slot_clicked(zone_number: int, player_id: int)
signal strategy_slot_clicked(strategy_index: int, player_id: int)

@export var player_id: int = 0
@export var is_opponent: bool = false

var zone_slots: Array[VRSlot3D] = []
var strategy_slots: Array[VRSlot3D] = []
var monster_slot: VRSlot3D
var deck_indicator: MeshInstance3D
var discard_indicator: MeshInstance3D

# Labels rendered as Label3D
var rage_label: Label3D
var cp_label: Label3D
var threat_label: Label3D
var deck_count_label: Label3D
var discard_count_label: Label3D

# Layout constants (meters, relative to board center)
# Board is roughly 55cm wide x 32cm deep per player
const BOARD_WIDTH := 0.55
const BOARD_DEPTH := 0.32

# Card spacing
const CARD_SPACING_X := 0.07   # 70mm between card centers
const CARD_SPACING_Z := 0.10   # 100mm between rows

# Row Z offsets from board center (negative = closer to player)
const BACK_ROW_Z := 0.05       # Back row (zones 1-5) slightly farther
const FRONT_ROW_Z := -0.05     # Front row (zones 6-8) closer to player

var card_scene: PackedScene = preload("res://scenes/vr/VRCard3D.tscn")


func _ready() -> void:
	_build_zones()
	_build_strategy_zones()
	_build_monster_slot()
	_build_deck_discard()
	_build_labels()


func _build_zones() -> void:
	# 8 battle zones arranged on the table
	# Back row: Zone1(leftmost) through Zone5(right)
	# Front row: Zone6(right), Zone7(center), Zone8(left)
	zone_slots.resize(8)

	# Back row: Zones 1-5
	for i in range(5):
		var slot := VRSlot3D.new()
		slot.name = "Zone%d" % (i + 1)
		slot.zone_number = i + 1
		slot.player_id = player_id
		slot.position = _get_zone_position(i)
		slot.slot_clicked.connect(_on_zone_clicked)
		add_child(slot)
		zone_slots[i] = slot

	# Front row: Zones 6-8 (positioned right to left to match playmat)
	for i in range(3):
		var zone_idx := 5 + i  # 5=Zone6, 6=Zone7, 7=Zone8
		var slot := VRSlot3D.new()
		slot.name = "Zone%d" % (zone_idx + 1)
		slot.zone_number = zone_idx + 1
		slot.player_id = player_id
		slot.position = _get_zone_position(zone_idx)
		slot.slot_clicked.connect(_on_zone_clicked)
		add_child(slot)
		zone_slots[zone_idx] = slot


func _get_zone_position(zone_idx: int) -> Vector3:
	var z_sign := -1.0 if is_opponent else 1.0

	if zone_idx < 5:
		# Back row: zones 1-5 (spread across width)
		var x := (zone_idx - 2) * CARD_SPACING_X  # Centered on 0
		var z := BACK_ROW_Z * z_sign
		return Vector3(x, 0, z)
	else:
		# Front row: zones 6-8 (right-aligned with zones 3-5)
		var front_idx := zone_idx - 5  # 0=Z6, 1=Z7, 2=Z8
		var x := (2 - front_idx) * CARD_SPACING_X  # Right to left
		var z := FRONT_ROW_Z * z_sign
		return Vector3(x, 0, z)


func _build_strategy_zones() -> void:
	strategy_slots.resize(3)
	var z_sign := -1.0 if is_opponent else 1.0

	for i in range(3):
		var slot := VRSlot3D.new()
		slot.name = "Strategy%d" % (i + 1)
		slot.zone_number = i + 1
		slot.player_id = player_id
		slot.slot_type = "strategy"
		slot.is_landscape = true
		# Strategy zones to the left, stacked vertically
		var x := -BOARD_WIDTH / 2.0 + 0.04
		var z := (FRONT_ROW_Z + i * 0.04) * z_sign
		slot.position = Vector3(x, 0, z)
		slot.slot_clicked.connect(func(zn: int, pid: int): strategy_slot_clicked.emit(i, pid))
		add_child(slot)
		strategy_slots[i] = slot

	# Third strategy slot hidden by default
	strategy_slots[2].visible = false


func _build_monster_slot() -> void:
	monster_slot = VRSlot3D.new()
	monster_slot.name = "MonsterSlot"
	monster_slot.zone_number = 0
	monster_slot.player_id = player_id
	monster_slot.slot_type = "monster"
	var z_sign := -1.0 if is_opponent else 1.0
	monster_slot.position = Vector3(-BOARD_WIDTH / 2.0 + 0.04, 0, BACK_ROW_Z * z_sign)
	add_child(monster_slot)


func _build_deck_discard() -> void:
	var z_sign := -1.0 if is_opponent else 1.0

	# Deck indicator (right side, back row)
	deck_indicator = _create_indicator("DeckIndicator", Color(0.2, 0.3, 0.5, 0.4))
	deck_indicator.position = Vector3(BOARD_WIDTH / 2.0 - 0.04, 0.0001, BACK_ROW_Z * z_sign)
	add_child(deck_indicator)

	# Discard indicator (right side, front row)
	discard_indicator = _create_indicator("DiscardIndicator", Color(0.5, 0.2, 0.2, 0.4))
	discard_indicator.position = Vector3(BOARD_WIDTH / 2.0 - 0.04, 0.0001, FRONT_ROW_Z * z_sign)
	add_child(discard_indicator)


func _create_indicator(ind_name: String, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = ind_name
	var quad := QuadMesh.new()
	quad.size = Vector2(VRCard3D.CARD_WIDTH, VRCard3D.CARD_HEIGHT)
	mesh_inst.mesh = quad
	mesh_inst.rotation.x = -PI / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	return mesh_inst


func _build_labels() -> void:
	var z_sign := -1.0 if is_opponent else 1.0

	# Rage label (between strategy and front row)
	rage_label = _create_label("RageLabel", "Rage: 0")
	rage_label.position = Vector3(-BOARD_WIDTH / 2.0 + 0.12, 0.002, FRONT_ROW_Z * z_sign)
	add_child(rage_label)

	# CP label
	cp_label = _create_label("CPLabel", "CP: 0")
	cp_label.position = Vector3(-BOARD_WIDTH / 2.0 + 0.12, 0.002, (FRONT_ROW_Z - 0.02) * z_sign)
	add_child(cp_label)

	# Threat label
	threat_label = _create_label("ThreatLabel", "Threat: 0")
	threat_label.position = Vector3(-BOARD_WIDTH / 2.0 + 0.12, 0.002, (FRONT_ROW_Z - 0.04) * z_sign)
	add_child(threat_label)

	# Deck count
	deck_count_label = _create_label("DeckCount", "0")
	deck_count_label.position = deck_indicator.position + Vector3(0, 0.002, 0.005 * z_sign)
	add_child(deck_count_label)

	# Discard count
	discard_count_label = _create_label("DiscardCount", "0")
	discard_count_label.position = discard_indicator.position + Vector3(0, 0.002, 0.005 * z_sign)
	add_child(discard_count_label)


func _create_label(label_name: String, text: String) -> Label3D:
	var label := Label3D.new()
	label.name = label_name
	label.text = text
	label.font_size = 32
	label.pixel_size = 0.0005
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation.x = -PI / 2.0  # Lie flat on table
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.outline_size = 4
	label.no_depth_test = true
	return label


## Sync this board's visual state to match a PlayerState — same signature as 2D PlayerBoard.
func sync_to_state(player_state: PlayerState, cp_modifier: int = 0, threat_modifier: int = 0, zone_cp_mods: Array = [], _strategy_cp_mods: Array = [], _zone_rank_mods: Array = [], _monster_cp_mod: int = 0) -> void:
	_sync_zones(player_state)
	_sync_strategy_zones(player_state)
	_sync_monster(player_state)
	_sync_info(player_state, cp_modifier, threat_modifier)


func _sync_zones(state: PlayerState) -> void:
	for i in range(mini(zone_slots.size(), 8)):
		var slot := zone_slots[i]
		if not slot:
			continue

		# Monster zone — managed separately
		if mini(state.monster_zone - 1, zone_slots.size() - 1) == i:
			slot.set_monster_marker(true)
			if slot.has_card():
				slot.remove_card(true)
			continue

		slot.set_monster_marker(false)
		var zone_data: Dictionary = state.get_zone_top_card(i)

		if zone_data.is_empty() and slot.has_card():
			slot.remove_card(true)
		elif not zone_data.is_empty() and not slot.has_card():
			var vr_card: VRCard3D = card_scene.instantiate()
			vr_card.set_card_data_dict(zone_data)
			slot.place_card(vr_card, false)
		elif not zone_data.is_empty() and slot.has_card():
			slot.get_card().set_card_data_dict(zone_data)


func _sync_strategy_zones(state: PlayerState) -> void:
	var zone_count: int = state.strategy_zones.size()

	# Show third slot if needed
	if zone_count >= 3 and strategy_slots.size() >= 3:
		strategy_slots[2].visible = true

	for i in range(mini(strategy_slots.size(), zone_count)):
		var slot := strategy_slots[i]
		if not slot:
			continue
		var sz_data: Dictionary = state.strategy_zones[i]

		if sz_data.is_empty() and slot.has_card():
			slot.remove_card(true)
		elif not sz_data.is_empty() and not slot.has_card():
			var vr_card: VRCard3D = card_scene.instantiate()
			vr_card.set_card_data_dict(sz_data)
			slot.place_card(vr_card, false)
		elif not sz_data.is_empty() and slot.has_card():
			slot.get_card().set_card_data_dict(sz_data)


func _sync_monster(state: PlayerState) -> void:
	if state.current_monster.is_empty():
		if monster_slot.has_card():
			monster_slot.remove_card(true)
		return

	if not monster_slot.has_card():
		var vr_card: VRCard3D = card_scene.instantiate()
		vr_card.set_card_data_dict(state.current_monster)
		monster_slot.place_card(vr_card, false)
	else:
		monster_slot.get_card().set_card_data_dict(state.current_monster)

	# Position monster card at the monster's current zone
	var zone_idx := mini(state.monster_zone - 1, zone_slots.size() - 1)
	if zone_idx >= 0 and zone_idx < zone_slots.size():
		var target_zone := zone_slots[zone_idx]
		# Monster card sits in its own slot but visually we can show its zone position
		# For now, just keep it in the monster slot


func _sync_info(state: PlayerState, cp_modifier: int, threat_modifier: int) -> void:
	rage_label.text = "Rage: %d" % state.rage

	var threat := state.get_threat_level() + threat_modifier
	threat_label.text = "Threat: %d" % threat

	# CP display (sum of all zone CPs)
	var total_cp := cp_modifier
	for i in range(8):
		var zone_data: Dictionary = state.get_zone_top_card(i)
		if not zone_data.is_empty():
			total_cp += zone_data.get("cp", 0)
	cp_label.text = "CP: %d" % total_cp

	deck_count_label.text = "%d" % state.main_deck.size()
	discard_count_label.text = "%d" % state.discard_pile.size()


func highlight_valid_zones(valid_zone_indices: Array) -> void:
	for i in range(zone_slots.size()):
		zone_slots[i].set_highlighted(i in valid_zone_indices)


func clear_highlights() -> void:
	for slot in zone_slots:
		slot.set_highlighted(false)
	for slot in strategy_slots:
		slot.set_highlighted(false)


func _on_zone_clicked(zone_number: int, pid: int) -> void:
	zone_slot_clicked.emit(zone_number, pid)
