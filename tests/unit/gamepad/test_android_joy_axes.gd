extends GdUnitTestSuite

## AndroidJoyAxes — re-derives which Godot axis index each SDL axis lands on
## from the Android AXIS_* ids a pad reports (Godot sorts them, hats
## excluded) and builds a corrected mapping only when the "Default Android
## Gamepad" fallback (a0-a3 sticks, a4/a5 triggers) would misread the pad.
## The JavaClassWrapper query is Android-only; this covers the pure logic.

const A := preload("res://scripts/input/android_joy_axes.gd")


func test_standard_trigger_axes_match_fallback() -> void:
	# X, Y, Z, RZ, LTRIGGER, RTRIGGER (+ hats) — the layout the fallback assumes.
	var axes: Array[int] = [A.AXIS_X, A.AXIS_Y, A.AXIS_Z, A.AXIS_RZ,
			A.AXIS_HAT_X, A.AXIS_HAT_Y, A.AXIS_LTRIGGER, A.AXIS_RTRIGGER]
	assert_dict(A.godot_axis_indices(axes)).is_equal(A.FALLBACK_AXES)
	assert_str(A.mapping_for("guid", "Pad", axes)).is_empty()


func test_gas_brake_triggers_are_swapped_back() -> void:
	# GAS (22, right) sorts before BRAKE (23, left): RT lands on a4.
	var axes: Array[int] = [A.AXIS_X, A.AXIS_Y, A.AXIS_Z, A.AXIS_RZ,
			A.AXIS_HAT_X, A.AXIS_HAT_Y, A.AXIS_GAS, A.AXIS_BRAKE]
	var indices := A.godot_axis_indices(axes)
	assert_int(indices["lefttrigger"]).is_equal(5)
	assert_int(indices["righttrigger"]).is_equal(4)
	var mapping := A.mapping_for("5468", "Thor Controller", axes)
	assert_str(mapping).starts_with("5468,Thor Controller,")
	assert_str(mapping).contains("lefttrigger:a5")
	assert_str(mapping).contains("righttrigger:a4")
	assert_str(mapping).contains("leftx:a0")
	assert_str(mapping).contains(A.FALLBACK_BUTTONS)


func test_pad_mirroring_both_trigger_kinds_uses_dedicated_axes() -> void:
	# LTRIGGER/RTRIGGER sort first (a4/a5); GAS/BRAKE trail as a6/a7.
	var axes: Array[int] = [A.AXIS_X, A.AXIS_Y, A.AXIS_Z, A.AXIS_RZ,
			A.AXIS_LTRIGGER, A.AXIS_RTRIGGER, A.AXIS_GAS, A.AXIS_BRAKE]
	assert_str(A.mapping_for("guid", "Pad", axes)).is_empty()


func test_pad_without_trigger_axes_is_left_alone() -> void:
	# Digital triggers (button keycodes) — no axis to correct.
	var axes: Array[int] = [A.AXIS_X, A.AXIS_Y, A.AXIS_Z, A.AXIS_RZ]
	var indices := A.godot_axis_indices(axes)
	assert_bool(indices.has("lefttrigger")).is_false()
	assert_str(A.mapping_for("guid", "Pad", axes)).is_empty()


func test_extra_stick_axes_shift_the_right_stick_and_triggers() -> void:
	# X Y Z RX RY RZ LT RT: the fallback reads RX as righty and RZ as LT.
	var axes: Array[int] = [A.AXIS_X, A.AXIS_Y, A.AXIS_Z, A.AXIS_RX, A.AXIS_RY,
			A.AXIS_RZ, A.AXIS_LTRIGGER, A.AXIS_RTRIGGER]
	var indices := A.godot_axis_indices(axes)
	assert_int(indices["rightx"]).is_equal(2)
	assert_int(indices["righty"]).is_equal(5)
	assert_int(indices["lefttrigger"]).is_equal(6)
	assert_int(indices["righttrigger"]).is_equal(7)
	assert_str(A.mapping_for("guid", "Pad", axes)).contains("righty:a5")


func test_duplicates_and_unsorted_input_match_java_ordering() -> void:
	var axes: Array[int] = [A.AXIS_BRAKE, A.AXIS_GAS, A.AXIS_RZ, A.AXIS_Z,
			A.AXIS_Y, A.AXIS_X, A.AXIS_GAS, A.AXIS_HAT_Y]
	var indices := A.godot_axis_indices(axes)
	assert_int(indices["righttrigger"]).is_equal(4)
	assert_int(indices["lefttrigger"]).is_equal(5)


func test_comma_in_joy_name_cannot_break_the_mapping() -> void:
	var axes: Array[int] = [A.AXIS_X, A.AXIS_Y, A.AXIS_Z, A.AXIS_RZ,
			A.AXIS_GAS, A.AXIS_BRAKE]
	var mapping := A.mapping_for("guid", "Pad, Inc", axes)
	assert_str(mapping.get_slice(",", 1)).is_equal("Pad  Inc")


func test_query_is_empty_off_android() -> void:
	assert_dict(AndroidJoyAxes.query_device_axes()).is_empty()


func test_corrected_mapping_parses() -> void:
	# Input.add_joy_mapping must accept the string without errors; registered
	# under a throwaway GUID so no real pad is affected.
	var axes: Array[int] = [A.AXIS_X, A.AXIS_Y, A.AXIS_Z, A.AXIS_RZ,
			A.AXIS_GAS, A.AXIS_BRAKE]
	var guid := "00000000000000000000000000test01"
	Input.add_joy_mapping(A.mapping_for(guid, "Test Pad", axes), false)
	Input.remove_joy_mapping(guid)
