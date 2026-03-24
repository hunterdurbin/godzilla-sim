extends Node

## Autoload singleton that manages XR initialization and mode detection.
## When xr/openxr/enabled is true in project settings, Godot auto-initializes
## OpenXR at engine startup. This autoload detects that and exposes is_vr_mode().

signal xr_initialized
signal xr_failed(reason: String)
signal xr_focus_gained
signal xr_focus_lost

var xr_interface: XRInterface
var _vr_active: bool = false


func _ready() -> void:
	if not ProjectSettings.get_setting("xr/openxr/enabled", false):
		print("[XRManager] OpenXR not enabled in project settings")
		return

	xr_interface = XRServer.find_interface("OpenXR")
	if not xr_interface:
		print("[XRManager] No OpenXR interface found — running in flat mode")
		return

	# The engine may have already initialized OpenXR from project settings.
	# Check is_initialized() first; only call initialize() if needed.
	if not xr_interface.is_initialized():
		if not xr_interface.initialize():
			print("[XRManager] OpenXR failed to initialize — running in flat mode")
			xr_failed.emit("OpenXR initialization failed")
			xr_interface = null
			return
		print("[XRManager] OpenXR initialized by XRManager")
	else:
		print("[XRManager] OpenXR was already initialized by engine")

	_vr_active = true

	xr_interface.session_begun.connect(_on_session_begun)
	xr_interface.session_stopping.connect(_on_session_stopping)
	xr_interface.session_focussed.connect(_on_session_focussed)
	xr_interface.session_visible.connect(_on_session_visible)

	xr_initialized.emit()


func is_vr_mode() -> bool:
	return _vr_active


func get_xr_interface() -> XRInterface:
	return xr_interface


## Enable XR rendering on the current viewport. Call from VR scenes.
func enable_xr_viewport() -> bool:
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		print("[XRManager] XR viewport enabled")
		return true
	push_warning("[XRManager] Cannot enable XR viewport — no initialized interface")
	return false


## Disable XR rendering. Call when leaving VR scenes.
func disable_xr_viewport() -> void:
	get_viewport().use_xr = false


## Map a flat-screen scene path to its VR equivalent when in VR mode.
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
