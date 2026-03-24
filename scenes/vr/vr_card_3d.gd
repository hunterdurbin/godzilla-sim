class_name VRCard3D
extends Node3D

## 3D card representation for VR. Two-sided textured quad at real card dimensions.
## Uses CardTextureProvider for texture loading (shared with 2D card.gd).

# Real card dimensions in meters (standard TCG: 63mm x 88mm)
const CARD_WIDTH := 0.063
const CARD_HEIGHT := 0.088
const CARD_THICKNESS := 0.001

signal card_pointed_at(card: VRCard3D)
signal card_point_exited(card: VRCard3D)
signal card_clicked(card: VRCard3D)
signal card_grabbed(card: VRCard3D)
signal card_released(card: VRCard3D)

var card_data: Dictionary = {}
var is_face_down: bool = false
var is_highlighted: bool = false
var is_selectable: bool = false

var _front_face: MeshInstance3D
var _back_face: MeshInstance3D
var _collision_area: Area3D
var _front_material: StandardMaterial3D
var _back_material: StandardMaterial3D
var _highlight_tween: Tween


func _ready() -> void:
	_build_card_mesh()
	_build_collision()
	_update_display()


func _build_card_mesh() -> void:
	# Front face (faces up, +Y)
	_front_face = MeshInstance3D.new()
	_front_face.name = "FrontFace"
	var front_quad := QuadMesh.new()
	front_quad.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	_front_face.mesh = front_quad
	# Rotate quad to lie flat (face up) — QuadMesh faces +Z by default
	_front_face.rotation.x = -PI / 2.0
	_front_face.position.y = CARD_THICKNESS / 2.0

	_front_material = StandardMaterial3D.new()
	_front_material.albedo_color = Color.WHITE
	_front_material.roughness = 0.7
	_front_material.metallic = 0.0
	_front_material.cull_mode = BaseMaterial3D.CULL_BACK
	_front_face.material_override = _front_material
	add_child(_front_face)

	# Back face (faces down, -Y)
	_back_face = MeshInstance3D.new()
	_back_face.name = "BackFace"
	var back_quad := QuadMesh.new()
	back_quad.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	_back_face.mesh = back_quad
	# Rotate to face downward
	_back_face.rotation.x = PI / 2.0
	_back_face.position.y = -CARD_THICKNESS / 2.0

	_back_material = StandardMaterial3D.new()
	_back_material.albedo_color = Color.WHITE
	_back_material.roughness = 0.7
	_back_material.cull_mode = BaseMaterial3D.CULL_BACK
	var back_tex := CardTextureProvider.get_card_back_texture()
	if back_tex:
		_back_material.albedo_texture = back_tex
	_back_face.material_override = _back_material
	add_child(_back_face)


func _build_collision() -> void:
	_collision_area = Area3D.new()
	_collision_area.name = "CardArea"
	# Set collision layer to 2 (cards) so pointer can detect them
	_collision_area.collision_layer = 2
	_collision_area.collision_mask = 0

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CARD_WIDTH, CARD_THICKNESS * 2.0, CARD_HEIGHT)
	col.shape = box
	_collision_area.add_child(col)

	_collision_area.mouse_entered.connect(_on_pointer_entered)
	_collision_area.mouse_exited.connect(_on_pointer_exited)
	_collision_area.input_event.connect(_on_input_event)

	add_child(_collision_area)


func set_card_data_dict(data: Dictionary) -> void:
	card_data = data
	if is_node_ready():
		_update_display()


func set_face_down(face_down: bool) -> void:
	is_face_down = face_down
	if is_node_ready():
		_update_visibility()


func set_highlight(enabled: bool) -> void:
	is_highlighted = enabled
	if not is_node_ready():
		return

	if _highlight_tween:
		_highlight_tween.kill()

	if enabled:
		_front_material.emission_enabled = true
		_front_material.emission = Color(1.0, 0.85, 0.2)
		_highlight_tween = create_tween().set_loops()
		_highlight_tween.tween_property(_front_material, "emission_energy_multiplier", 0.4, 0.6)
		_highlight_tween.tween_property(_front_material, "emission_energy_multiplier", 0.1, 0.6)
	else:
		_front_material.emission_enabled = false
		_front_material.emission_energy_multiplier = 0.0


## Animate card flipping face up/down
func animate_flip(target_face_down: bool, duration: float = 0.3) -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	# Rotate 180 degrees around local Z axis (card lies flat, so Z is the flip axis)
	var target_rot := PI if target_face_down else 0.0
	tw.tween_property(self, "rotation:z", target_rot, duration)
	tw.tween_callback(set_face_down.bind(target_face_down))


## Animate card moving to a target position
func animate_to(target_pos: Vector3, duration: float = 0.3) -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "position", target_pos, duration)


## Animate card lifting slightly (hover feedback)
func animate_hover_lift(lift_amount: float = 0.01) -> void:
	if _highlight_tween:
		_highlight_tween.kill()
	_highlight_tween = create_tween()
	_highlight_tween.set_ease(Tween.EASE_OUT)
	_highlight_tween.set_trans(Tween.TRANS_CUBIC)
	_highlight_tween.tween_property(self, "position:y", position.y + lift_amount, 0.15)


## Return card to base Y position
func animate_hover_return(base_y: float) -> void:
	if _highlight_tween:
		_highlight_tween.kill()
	_highlight_tween = create_tween()
	_highlight_tween.set_ease(Tween.EASE_OUT)
	_highlight_tween.set_trans(Tween.TRANS_CUBIC)
	_highlight_tween.tween_property(self, "position:y", base_y, 0.15)


func _update_display() -> void:
	if card_data.is_empty():
		return

	var tex := CardTextureProvider.get_card_texture(card_data)
	if tex:
		_front_material.albedo_texture = tex

	_update_visibility()


func _update_visibility() -> void:
	# When face down, the card is rotated 180 degrees so the back faces up
	# For simplicity, just toggle visibility of front/back
	_front_face.visible = not is_face_down
	_back_face.visible = true  # Back always visible (it's the underside)


func _on_pointer_entered() -> void:
	card_pointed_at.emit(self)


func _on_pointer_exited() -> void:
	card_point_exited.emit(self)


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(self)
