extends Node

## Autoload singleton for XR mode detection.
## The actual XR initialization is handled by godot-xr-tools StartXR node,
## which is added to VR scenes. This autoload just detects if XR is available.

var xr_interface: XRInterface
var _vr_available: bool = false


func _ready() -> void:
	if not ProjectSettings.get_setting("xr/openxr/enabled", false):
		return

	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface:
		_vr_available = true
		print("[XRManager] OpenXR interface found — VR available")
	else:
		print("[XRManager] No OpenXR interface — flat mode only")


## Returns true if an XR interface is available (headset may be connected).
func is_vr_mode() -> bool:
	return _vr_available


## Map a flat-screen scene path to its VR equivalent when in VR mode.
const VR_SCENE_MAP := {
	"res://scenes/board/GameBoard.tscn": "res://scenes/vr/VRGameBoard3D.tscn",
}


func get_scene_path(flat_path: String) -> String:
	if _vr_available and VR_SCENE_MAP.has(flat_path):
		return VR_SCENE_MAP[flat_path]
	return flat_path
