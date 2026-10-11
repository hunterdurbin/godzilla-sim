class_name AndroidJoyAxes
extends RefCounted
## Corrects Godot's axis numbering for Android pads on the fallback mapping.
##
## Godot's Android input layer (GodotInputHandler.onInputDeviceAdded) numbers
## a pad's axes by SORTING its Android AXIS_* ids (hats excluded) and hands the
## sorted POSITION to Input as the axis index. Pads missing from the controller
## DB then get "Default Android Gamepad", which assumes leftx:a0 lefty:a1
## rightx:a2 righty:a3 lefttrigger:a4 righttrigger:a5. That only holds for pads
## reporting X/Y/Z/RZ/LTRIGGER/RTRIGGER; a pad reporting its triggers as
## GAS(22, right)/BRAKE(23, left) sorts GAS first and arrives with swapped
## triggers (godotengine/godot#56181 — SDL special-cases this, Godot doesn't).
##
## query_device_axes() asks Android (through JavaClassWrapper) which axes each
## device really reports; mapping_for() turns that into a per-GUID mapping
## with each SDL axis pointed at the index Godot actually assigned it.
## Pure logic is static and platform-free so unit tests cover it on desktop.

const AXIS_X := 0
const AXIS_Y := 1
const AXIS_Z := 11
const AXIS_RX := 12
const AXIS_RY := 13
const AXIS_RZ := 14
const AXIS_HAT_X := 15
const AXIS_HAT_Y := 16
const AXIS_LTRIGGER := 17
const AXIS_RTRIGGER := 18
const AXIS_GAS := 22
const AXIS_BRAKE := 23

## InputDevice.SOURCE_JOYSTICK / SOURCE_GAMEPAD — the motion-range sources
## Godot's Java layer keeps (same filter, so the sorted lists match).
const SOURCE_JOYSTICK := 0x01000010
const SOURCE_GAMEPAD := 0x00000401

## SDL axis -> Android axes that can carry it, in preference order (the
## dedicated trigger axes win over GAS/BRAKE when a pad mirrors both).
const SDL_AXIS_SOURCES := {
	"leftx": [AXIS_X],
	"lefty": [AXIS_Y],
	"rightx": [AXIS_Z, AXIS_RX],
	"righty": [AXIS_RZ, AXIS_RY],
	"lefttrigger": [AXIS_LTRIGGER, AXIS_BRAKE],
	"righttrigger": [AXIS_RTRIGGER, AXIS_GAS],
}

## What "Default Android Gamepad" (Godot 4.6) assumes for each SDL axis.
const FALLBACK_AXES := {
	"leftx": 0, "lefty": 1, "rightx": 2, "righty": 3,
	"lefttrigger": 4, "righttrigger": 5,
}

## The fallback mapping's button/hat half, copied verbatim so a corrected
## mapping changes nothing but the axes.
const FALLBACK_BUTTONS := "a:b0,b:b1,x:b2,y:b3,back:b4,start:b6," \
		+ "leftstick:b7,rightstick:b8,leftshoulder:b9,rightshoulder:b10," \
		+ "dpup:h0.1,dpright:h0.2,dpdown:h0.4,dpleft:h0.8," \
		+ "dpup:b11,dpdown:b12,dpleft:b13,dpright:b14"


## SDL axis name -> the Godot axis index it lands on, for a device reporting
## `android_axes`. Mirrors the Java layer: hats dropped, duplicates dropped,
## ascending sort. SDL axes the device can't carry are absent.
static func godot_axis_indices(android_axes: Array[int]) -> Dictionary:
	var sorted: Array[int] = []
	for axis: int in android_axes:
		if axis == AXIS_HAT_X or axis == AXIS_HAT_Y or sorted.has(axis):
			continue
		sorted.append(axis)
	sorted.sort()
	var out := {}
	for sdl_axis: String in SDL_AXIS_SOURCES:
		for candidate: int in SDL_AXIS_SOURCES[sdl_axis]:
			var index := sorted.find(candidate)
			if index >= 0:
				out[sdl_axis] = index
				break
	return out


## Full mapping string for Input.add_joy_mapping, or "" when the fallback
## already reads every axis the device has (nothing to correct). Axes the
## device lacks are left out rather than pointed at a wrong index.
static func mapping_for(guid: String, joy_name: String, android_axes: Array[int]) -> String:
	var indices := godot_axis_indices(android_axes)
	var differs := false
	for sdl_axis: String in indices:
		if indices[sdl_axis] != FALLBACK_AXES[sdl_axis]:
			differs = true
	if not differs:
		return ""
	var entries := PackedStringArray([guid, joy_name.replace(",", " "), FALLBACK_BUTTONS])
	for sdl_axis: String in indices:
		entries.append("%s:a%d" % [sdl_axis, indices[sdl_axis]])
	return ",".join(entries)


## Android device name -> its joystick/gamepad axis ids, for every input
## device Android reports. Names match Input.get_joy_name() (Godot's Java
## layer passes InputDevice.getName() through unchanged). Empty off Android
## or when the Java bridge returns anything unexpected.
static func query_device_axes() -> Dictionary:
	var out := {}
	if OS.get_name() != "Android":
		return out
	var input_device: JavaClass = JavaClassWrapper.wrap("android.view.InputDevice")
	if input_device == null:
		return out
	var ids: Variant = input_device.getDeviceIds()
	if not (ids is PackedInt32Array or ids is Array):
		return out
	for id: int in ids:
		var device: Variant = input_device.getDevice(id)
		if not device is JavaObject:
			continue
		var device_name := str(device.getName())
		if out.has(device_name):
			continue
		# toArray(), not List.get(i): JavaObject resolves Godot methods first,
		# and Object.get() would shadow the Java one.
		var ranges: Variant = device.getMotionRanges()
		if not ranges is JavaObject:
			continue
		var range_array: Variant = ranges.toArray()
		if not range_array is Array:
			continue
		var axes: Array[int] = []
		for motion_range: Variant in range_array:
			if not motion_range is JavaObject:
				continue
			var source := int(motion_range.getSource())
			if (source & SOURCE_JOYSTICK) != SOURCE_JOYSTICK \
					and (source & SOURCE_GAMEPAD) != SOURCE_GAMEPAD:
				continue
			axes.append(int(motion_range.getAxis()))
		if not axes.is_empty():
			out[device_name] = axes
	return out
