extends Node
## Tracks the current input method (touch vs mouse) at runtime.
## Switches dynamically so hybrid devices (touchscreen laptops) work correctly:
## mouse input → desktop behavior, touch input → touch behavior.
##
## Registered as autoload "TouchHelper" in project.godot.
## Call TouchHelper.is_touch_device() from anywhere.

var _touch_mode: bool = false
var _touch_frame: int = -1
var _is_mobile: bool = false


func is_touch_device() -> bool:
	return _touch_mode


func _ready() -> void:
	# On mobile platforms, always use touch mode — no dynamic switching.
	# The emulator may send mouse events instead of InputEventScreenTouch,
	# which would incorrectly flip _touch_mode to false without this guard.
	_is_mobile = OS.get_name() in ["Android", "iOS"] or OS.has_feature("mobile") \
		or "--mobile" in OS.get_cmdline_args()
	if _is_mobile or DisplayServer.is_touchscreen_available():
		_touch_mode = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Bridge Android back button to ui_cancel so scene handlers can react
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)


func _input(event: InputEvent) -> void:
	if _is_mobile:
		return  # Always touch mode on mobile — skip dynamic switching
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_mode = true
		_touch_frame = Engine.get_process_frames()
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# Emulated mouse events from touch arrive in the same frame as the
		# InputEventScreenTouch, so ignore mouse events from the touch frame.
		if Engine.get_process_frames() != _touch_frame:
			_touch_mode = false
