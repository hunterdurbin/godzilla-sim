extends Node3D

## 3D environment for VR card game — room, table, and lighting.
## Table dimensions match real TCG playmat scale for natural VR interaction.

# Table surface dimensions in meters (play area for both players)
const TABLE_WIDTH := 1.2   # ~120cm wide
const TABLE_DEPTH := 0.8   # ~80cm deep (40cm per player side)
const TABLE_HEIGHT := 0.75  # Standard table height ~75cm
const TABLE_THICKNESS := 0.05

# Room dimensions
const ROOM_WIDTH := 4.0
const ROOM_DEPTH := 4.0
const ROOM_HEIGHT := 3.0


func _ready() -> void:
	_build_room()
	_build_table()
	_build_lighting()


func _build_room() -> void:
	# Floor
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(ROOM_WIDTH, ROOM_DEPTH)
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	floor_inst.name = "Floor"
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.4, 0.3, 0.2)  # Wood floor
	floor_mat.roughness = 0.8
	floor_inst.material_override = floor_mat
	add_child(floor_inst)

	# Walls (simple box for each wall)
	_add_wall("BackWall", Vector3(0, ROOM_HEIGHT / 2.0, -ROOM_DEPTH / 2.0), Vector3(ROOM_WIDTH, ROOM_HEIGHT, 0.1))
	_add_wall("FrontWall", Vector3(0, ROOM_HEIGHT / 2.0, ROOM_DEPTH / 2.0), Vector3(ROOM_WIDTH, ROOM_HEIGHT, 0.1))
	_add_wall("LeftWall", Vector3(-ROOM_WIDTH / 2.0, ROOM_HEIGHT / 2.0, 0), Vector3(0.1, ROOM_HEIGHT, ROOM_DEPTH))
	_add_wall("RightWall", Vector3(ROOM_WIDTH / 2.0, ROOM_HEIGHT / 2.0, 0), Vector3(0.1, ROOM_HEIGHT, ROOM_DEPTH))

	# Ceiling
	var ceil_mesh := PlaneMesh.new()
	ceil_mesh.size = Vector2(ROOM_WIDTH, ROOM_DEPTH)
	var ceil_inst := MeshInstance3D.new()
	ceil_inst.mesh = ceil_mesh
	ceil_inst.name = "Ceiling"
	ceil_inst.position = Vector3(0, ROOM_HEIGHT, 0)
	ceil_inst.rotation.x = PI  # Flip to face downward
	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = Color(0.5, 0.48, 0.45)
	ceil_mat.roughness = 0.9
	ceil_inst.material_override = ceil_mat
	add_child(ceil_inst)


func _add_wall(wall_name: String, pos: Vector3, wall_size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = wall_size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.name = wall_name
	inst.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.45, 0.4)  # Wall
	mat.roughness = 0.85
	inst.material_override = mat
	add_child(inst)


func _build_table() -> void:
	var table := StaticBody3D.new()
	table.name = "Table"
	add_child(table)

	# Table top
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(TABLE_WIDTH, TABLE_THICKNESS, TABLE_DEPTH)
	var top_inst := MeshInstance3D.new()
	top_inst.mesh = top_mesh
	top_inst.name = "TableTop"
	top_inst.position = Vector3(0, TABLE_HEIGHT, 0)
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.25, 0.15, 0.08)  # Dark wood table
	top_mat.roughness = 0.6
	top_mat.metallic = 0.05
	top_inst.material_override = top_mat
	table.add_child(top_inst)

	# Table collision
	var col_shape := CollisionShape3D.new()
	col_shape.name = "TableCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(TABLE_WIDTH, TABLE_THICKNESS, TABLE_DEPTH)
	col_shape.shape = box
	col_shape.position = Vector3(0, TABLE_HEIGHT, 0)
	table.add_child(col_shape)

	# Play mat on table surface (slightly above table)
	var mat_mesh := PlaneMesh.new()
	mat_mesh.size = Vector2(TABLE_WIDTH - 0.1, TABLE_DEPTH - 0.1)
	var mat_inst := MeshInstance3D.new()
	mat_inst.mesh = mat_mesh
	mat_inst.name = "PlayMat"
	mat_inst.position = Vector3(0, TABLE_HEIGHT + TABLE_THICKNESS / 2.0 + 0.001, 0)
	var mat_mat := StandardMaterial3D.new()
	mat_mat.albedo_color = Color(0.05, 0.15, 0.05)  # Dark green felt
	mat_mat.roughness = 0.95
	mat_inst.material_override = mat_mat
	table.add_child(mat_inst)

	# Table legs
	var leg_positions := [
		Vector3(-TABLE_WIDTH / 2.0 + 0.05, TABLE_HEIGHT / 2.0, -TABLE_DEPTH / 2.0 + 0.05),
		Vector3(TABLE_WIDTH / 2.0 - 0.05, TABLE_HEIGHT / 2.0, -TABLE_DEPTH / 2.0 + 0.05),
		Vector3(-TABLE_WIDTH / 2.0 + 0.05, TABLE_HEIGHT / 2.0, TABLE_DEPTH / 2.0 - 0.05),
		Vector3(TABLE_WIDTH / 2.0 - 0.05, TABLE_HEIGHT / 2.0, TABLE_DEPTH / 2.0 - 0.05),
	]
	for i in range(leg_positions.size()):
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.05, TABLE_HEIGHT, 0.05)
		var leg_inst := MeshInstance3D.new()
		leg_inst.mesh = leg_mesh
		leg_inst.name = "Leg%d" % (i + 1)
		leg_inst.position = leg_positions[i]
		leg_inst.material_override = top_mat
		table.add_child(leg_inst)


func _build_lighting() -> void:
	# World environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.25)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.5)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAP_LINEAR
	env.ssao_enabled = false  # Keep lightweight for Quest
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	# Overhead directional light (main)
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "OverheadLight"
	dir_light.position = Vector3(0, ROOM_HEIGHT - 0.1, 0)
	dir_light.rotation = Vector3(deg_to_rad(-70), 0, 0)
	dir_light.light_color = Color(1.0, 0.95, 0.85)
	dir_light.light_energy = 1.5
	dir_light.shadow_enabled = true
	add_child(dir_light)

	# Table spot light (focused on play area)
	var table_light := OmniLight3D.new()
	table_light.name = "TableLight1"
	table_light.position = Vector3(0, TABLE_HEIGHT + 0.8, 0)
	table_light.light_color = Color(1.0, 0.95, 0.9)
	table_light.light_energy = 3.0
	table_light.omni_range = 3.0
	table_light.omni_attenuation = 1.0
	table_light.shadow_enabled = false
	add_child(table_light)

	# Secondary fill light
	var fill_light := OmniLight3D.new()
	fill_light.name = "TableLight2"
	fill_light.position = Vector3(0.3, TABLE_HEIGHT + 0.6, -0.2)
	fill_light.light_color = Color(0.9, 0.85, 0.8)
	fill_light.light_energy = 0.6
	fill_light.omni_range = 1.5
	fill_light.shadow_enabled = false
	add_child(fill_light)


## Returns the Y position of the table surface (top of table + play mat)
func get_table_surface_y() -> float:
	return TABLE_HEIGHT + TABLE_THICKNESS / 2.0 + 0.001
