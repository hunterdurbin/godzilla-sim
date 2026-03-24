extends Node3D

## Laser pointer for VR controllers. Raycasts from controller forward direction
## and detects VRSlot3D and VRCard3D intersections. Renders a visible laser beam.

signal pointed_at_slot(slot: VRSlot3D)
signal pointed_at_card(card: VRCard3D)
signal pointed_at_nothing()
signal trigger_pressed()
signal trigger_released()
signal grip_pressed()
signal grip_released()

@export var pointer_length: float = 2.0
@export var laser_color: Color = Color(0.3, 0.6, 1.0, 0.8)
@export var laser_hit_color: Color = Color(0.3, 1.0, 0.5, 0.9)

var _raycast: RayCast3D
var _laser_mesh: MeshInstance3D
var _laser_material: StandardMaterial3D
var _hit_dot: MeshInstance3D
var _current_target: Node = null
var _controller: XRController3D


func _ready() -> void:
	_controller = get_parent() as XRController3D

	_build_raycast()
	_build_laser()
	_build_hit_dot()

	if _controller:
		_controller.button_pressed.connect(_on_button_pressed)
		_controller.button_released.connect(_on_button_released)


func _build_raycast() -> void:
	_raycast = RayCast3D.new()
	_raycast.name = "PointerRay"
	_raycast.target_position = Vector3(0, 0, -pointer_length)
	_raycast.enabled = true
	# Detect layers: 2 (cards), 4 (zones/slots)
	_raycast.collision_mask = 2 | 4
	add_child(_raycast)


func _build_laser() -> void:
	_laser_mesh = MeshInstance3D.new()
	_laser_mesh.name = "LaserBeam"

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.001
	cylinder.bottom_radius = 0.001
	cylinder.height = pointer_length
	_laser_mesh.mesh = cylinder

	# Rotate cylinder to point along -Z (forward)
	_laser_mesh.rotation.x = PI / 2.0
	_laser_mesh.position.z = -pointer_length / 2.0

	_laser_material = StandardMaterial3D.new()
	_laser_material.albedo_color = laser_color
	_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_material.no_depth_test = true
	_laser_mesh.material_override = _laser_material

	add_child(_laser_mesh)


func _build_hit_dot() -> void:
	_hit_dot = MeshInstance3D.new()
	_hit_dot.name = "HitDot"
	var sphere := SphereMesh.new()
	sphere.radius = 0.005
	sphere.height = 0.01
	_hit_dot.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	_hit_dot.material_override = mat
	_hit_dot.visible = false
	add_child(_hit_dot)


func _process(_delta: float) -> void:
	if not _raycast:
		return

	if _raycast.is_colliding():
		var collider := _raycast.get_collider()
		var hit_point := _raycast.get_collision_point()
		var hit_distance := global_position.distance_to(hit_point)

		# Update laser to hit point
		_update_laser_length(hit_distance)
		_laser_material.albedo_color = laser_hit_color
		_hit_dot.visible = true
		_hit_dot.global_position = hit_point

		# Determine what we're pointing at
		var new_target := _resolve_target(collider)
		if new_target != _current_target:
			_on_target_changed(new_target)
	else:
		_update_laser_length(pointer_length)
		_laser_material.albedo_color = laser_color
		_hit_dot.visible = false

		if _current_target != null:
			_on_target_changed(null)


func _update_laser_length(length: float) -> void:
	var cylinder := _laser_mesh.mesh as CylinderMesh
	if cylinder:
		cylinder.height = length
		_laser_mesh.position.z = -length / 2.0


func _resolve_target(collider: Node) -> Node:
	# Walk up the tree to find VRSlot3D or VRCard3D
	var node := collider
	while node:
		if node is VRSlot3D or node is VRCard3D:
			return node
		node = node.get_parent()
	return null


func _on_target_changed(new_target: Node) -> void:
	_current_target = new_target

	if new_target == null:
		pointed_at_nothing.emit()
	elif new_target is VRSlot3D:
		pointed_at_slot.emit(new_target)
	elif new_target is VRCard3D:
		pointed_at_card.emit(new_target)


func _on_button_pressed(button_name: String) -> void:
	match button_name:
		"trigger_click":
			trigger_pressed.emit()
			_handle_trigger_on_target()
		"grip_click":
			grip_pressed.emit()


func _on_button_released(button_name: String) -> void:
	match button_name:
		"trigger_click":
			trigger_released.emit()
		"grip_click":
			grip_released.emit()


func _handle_trigger_on_target() -> void:
	if _current_target == null:
		return

	# Emit input_event on the Area3D so existing card/slot handlers fire
	if _current_target is VRSlot3D:
		var slot := _current_target as VRSlot3D
		slot.slot_clicked.emit(slot.zone_number, slot.player_id)
	elif _current_target is VRCard3D:
		var card := _current_target as VRCard3D
		card.card_clicked.emit(card)


func get_current_target() -> Node:
	return _current_target
