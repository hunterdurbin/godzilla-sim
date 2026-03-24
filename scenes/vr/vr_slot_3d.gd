class_name VRSlot3D
extends Node3D

## 3D zone slot on the VR game table. Holds a single VRCard3D.
## Collision area allows pointer ray detection for zone selection.

signal slot_pointed_at(slot: VRSlot3D)
signal slot_point_exited(slot: VRSlot3D)
signal slot_clicked(zone_number: int, player_id: int)

@export var zone_number: int = 1
@export var player_id: int = 0
@export var slot_type: String = "battle"  # "battle", "strategy", "monster", "deck", "discard"
@export var is_landscape: bool = false

var card: VRCard3D = null
var is_monster_zone: bool = false

var _border_mesh: MeshInstance3D
var _area: Area3D
var _border_material: StandardMaterial3D
var _default_border_color := Color(0.3, 0.3, 0.3, 0.5)
var _highlight_color := Color(0.3, 0.7, 1.0, 0.8)

var card_scene: PackedScene = preload("res://scenes/vr/VRCard3D.tscn")


func _ready() -> void:
	_build_border()
	_build_collision()


func _build_border() -> void:
	_border_mesh = MeshInstance3D.new()
	_border_mesh.name = "Border"

	var quad := QuadMesh.new()
	if is_landscape:
		quad.size = Vector2(VRCard3D.CARD_HEIGHT, VRCard3D.CARD_WIDTH)
	else:
		quad.size = Vector2(VRCard3D.CARD_WIDTH, VRCard3D.CARD_HEIGHT)
	_border_mesh.mesh = quad
	# Lie flat on table (face up)
	_border_mesh.rotation.x = -PI / 2.0
	_border_mesh.position.y = 0.0001  # Just above table surface

	_border_material = StandardMaterial3D.new()
	_border_material.albedo_color = _default_border_color
	_border_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_border_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_border_mesh.material_override = _border_material

	add_child(_border_mesh)


func _build_collision() -> void:
	_area = Area3D.new()
	_area.name = "SlotArea"
	# Collision layer 4 (zones/slots)
	_area.collision_layer = 4
	_area.collision_mask = 0

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	if is_landscape:
		box.size = Vector3(VRCard3D.CARD_HEIGHT, 0.005, VRCard3D.CARD_WIDTH)
	else:
		box.size = Vector3(VRCard3D.CARD_WIDTH, 0.005, VRCard3D.CARD_HEIGHT)
	col.shape = box
	_area.add_child(col)

	_area.mouse_entered.connect(_on_pointer_entered)
	_area.mouse_exited.connect(_on_pointer_exited)
	_area.input_event.connect(_on_input_event)

	add_child(_area)


func has_card() -> bool:
	return card != null


func get_card() -> VRCard3D:
	return card


func place_card(new_card: VRCard3D, animate: bool = true) -> void:
	if card:
		remove_card(true)

	card = new_card
	if card.get_parent():
		card.get_parent().remove_child(card)
	add_child(card)

	# Position card centered on slot, slightly above border
	var target_pos := Vector3(0, 0.001, 0)
	if is_landscape:
		card.rotation.y = PI / 2.0  # Rotate card for landscape

	if animate:
		card.animate_to(target_pos, 0.2)
	else:
		card.position = target_pos


func remove_card(free_card: bool = false) -> VRCard3D:
	var old_card := card
	card = null
	if old_card and free_card:
		old_card.queue_free()
		return null
	return old_card


func set_highlighted(enabled: bool) -> void:
	if enabled:
		_border_material.albedo_color = _highlight_color
		_border_material.emission_enabled = true
		_border_material.emission = _highlight_color
		_border_material.emission_energy_multiplier = 0.3
	else:
		_border_material.albedo_color = _default_border_color
		_border_material.emission_enabled = false


func set_monster_marker(enabled: bool) -> void:
	is_monster_zone = enabled
	# Visual indicator for monster position
	if enabled:
		_border_material.albedo_color = Color(0.8, 0.2, 0.1, 0.6)
	elif not is_monster_zone:
		_border_material.albedo_color = _default_border_color


func _on_pointer_entered() -> void:
	slot_pointed_at.emit(self)


func _on_pointer_exited() -> void:
	slot_point_exited.emit(self)


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(zone_number, player_id)
