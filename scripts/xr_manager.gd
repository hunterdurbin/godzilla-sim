extends Node

## Autoload singleton that manages XR initialization and mode detection.
## Detects available XR hardware at startup and provides is_vr_mode() for
## the rest of the codebase to branch between flat-screen and VR presentation.

signal xr_initialized
signal xr_failed(reason: String)
signal xr_focus_gained
signal xr_focus_lost

var xr_interface: XRInterface
var _vr_active: bool = false


func _ready() -> void:
	# Only attempt XR init if OpenXR is enabled in project settings
	if not ProjectSettings.get_setting("xr/openxr/enabled", false):
		return

	xr_interface = XRServer.find_interface("OpenXR")
	if not xr_interface:
		print("[XRManager] No OpenXR interface found — running in flat mode")
		return

	xr_interface.session_begun.connect(_on_session_begun)
	xr_interface.session_stopping.connect(_on_session_stopping)
	xr_interface.session_focussed.connect(_on_session_focussed)
	xr_interface.session_visible.connect(_on_session_visible)

	if not xr_interface.initialize():
		print("[XRManager] OpenXR failed to initialize — running in flat mode")
		xr_failed.emit("OpenXR initialization failed")
		xr_interface = null
		return

	print("[XRManager] OpenXR initialized successfully")
	_vr_active = true

	# Configure the main viewport for XR
	get_viewport().use_xr = true

	# Let XR handle frame timing instead of vsync
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	xr_initialized.emit()


func is_vr_mode() -> bool:
	return _vr_active


func get_xr_interface() -> XRInterface:
	return xr_interface


## Map a flat-screen scene path to its VR equivalent when in VR mode.
## Returns the original path if no VR version exists or not in VR mode.
const VR_SCENE_MAP := {
	"res://scenes/board/GameBoard.tscn": "res://scenes/vr/VRGameBoard3D.tscn",
}


func get_scene_path(flat_path: String) -> String:
	if _vr_active and VR_SCENE_MAP.has(flat_path):
		return VR_SCENE_MAP[flat_path]
	return flat_path


func _on_session_begun() -> void:
	print("[XRManager] XR session begun")


func _on_session_stopping() -> void:
	print("[XRManager] XR session stopping")


func _on_session_focussed() -> void:
	print("[XRManager] XR session focused")
	xr_focus_gained.emit()


func _on_session_visible() -> void:
	print("[XRManager] XR session visible (lost focus)")
	xr_focus_lost.emit()
