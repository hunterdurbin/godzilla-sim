extends Node3D

## Minimal VR test scene. Run this with F6 to verify VR works.
## You should see a red cube floating in front of you and a white floor.

func _ready() -> void:
	# --- XR INIT ---
	var xr_interface = XRServer.find_interface("OpenXR")
	print("=== VR TEST ===")
	print("OpenXR interface: ", xr_interface)
	if xr_interface:
		print("  is_initialized: ", xr_interface.is_initialized())
		if not xr_interface.is_initialized():
			print("  Calling initialize()...")
			var ok = xr_interface.initialize()
			print("  initialize() result: ", ok)
		if xr_interface.is_initialized():
			get_viewport().use_xr = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			print("  >>> use_xr = true — VR SHOULD BE ACTIVE <<<")
		else:
			print("  FAIL: OpenXR not initialized after attempt")
	else:
		print("  FAIL: No OpenXR interface. Available interfaces:")
		for i in range(XRServer.get_interface_count()):
			print("    - ", XRServer.get_interface(i).get_name())

	# --- XR RIG ---
	var origin := XROrigin3D.new()
	origin.name = "XROrigin3D"
	var camera := XRCamera3D.new()
	camera.name = "XRCamera3D"
	camera.position.y = 1.7
	origin.add_child(camera)
	var left := XRController3D.new()
	left.name = "LeftHand"
	left.tracker = &"left_hand"
	origin.add_child(left)
	var right := XRController3D.new()
	right.name = "RightHand"
	right.tracker = &"right_hand"
	origin.add_child(right)
	add_child(origin)

	# --- ENVIRONMENT ---
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.3, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# --- LIGHT ---
	var light := DirectionalLight3D.new()
	light.rotation.x = deg_to_rad(-45)
	light.light_energy = 2.0
	add_child(light)

	# --- RED CUBE (should be right in front of you) ---
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = Vector3(0.5, 0.5, 0.5)
	var cube := MeshInstance3D.new()
	cube.mesh = cube_mesh
	cube.position = Vector3(0, 1.0, -2.0)
	var cube_mat := StandardMaterial3D.new()
	cube_mat.albedo_color = Color.RED
	cube.material_override = cube_mat
	add_child(cube)

	# --- GREEN CUBE (to the left) ---
	var cube2_mesh := BoxMesh.new()
	cube2_mesh.size = Vector3(0.3, 0.3, 0.3)
	var cube2 := MeshInstance3D.new()
	cube2.mesh = cube2_mesh
	cube2.position = Vector3(-1.0, 1.5, -1.5)
	var cube2_mat := StandardMaterial3D.new()
	cube2_mat.albedo_color = Color.GREEN
	cube2.material_override = cube2_mat
	add_child(cube2)

	# --- FLOOR ---
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(10, 10)
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.8, 0.8, 0.8)
	floor_inst.material_override = floor_mat
	add_child(floor_inst)

	print("=== VR TEST SCENE BUILT ===")
