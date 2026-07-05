extends Node
## Tracks whether the gamepad is the active input device and owns the
## focus-context stack that decides where controller focus lands.
##
## Third input mode alongside TouchHelper's touch-vs-mouse tracking (port of
## Slay the Spire 2's NControllerManager): any physical joypad input switches
## to gamepad mode; a real mouse click, deliberate mouse motion, or any touch
## switches back. On desktop the OS cursor is hidden and warped off-screen in
## gamepad mode so stale hover states can't fight the controller cursor; on
## touch platforms the warp is skipped entirely.
##
## Screens/overlays register a focus context (LIFO): the top context's
## provider Callable returns the Control that should hold focus in gamepad
## mode. Pushing a context is also how a modal blocks the layers beneath it
## (board navigation suspends unless it is the top context).
##
## Registered as autoload "GamepadHelper" in project.godot.

## Emitted when the gamepad becomes the active device.
signal gamepad_detected
## Emitted when mouse or touch becomes the active device again.
signal pointer_detected

## Spire's mouse-motion guard: deliberate movement only (velocity² > 100),
## and not the huge relative jump produced by our own off-screen warp.
const MOUSE_VELOCITY_SQ_MIN := 100.0
const MOUSE_RELATIVE_SQ_MAX := 250000.0
const WARP_POS := Vector2(-1000.0, -1000.0)

var _using_gamepad := false
var _last_mouse_pos := Vector2.ZERO
var _skip_mouse_frames := 0
## LIFO of {"owner": Node, "provider": Callable} — provider returns the
## Control to focus (or null).
var _focus_stack: Array[Dictionary] = []
## Controls registered via make_pad_focusable: FOCUS_ALL only in gamepad
## mode, FOCUS_NONE otherwise (so mouse clicks never leave a focus ring).
var _pad_focusables: Array[WeakRef] = []
@onready var _warp_allowed: bool = OS.get_name() in ["Windows", "macOS", "Linux"] \
		and not DisplayServer.is_touchscreen_available()


func is_using_gamepad() -> bool:
	return _using_gamepad


func _process(_delta: float) -> void:
	if _skip_mouse_frames > 0:
		_skip_mouse_frames -= 1


func _input(event: InputEvent) -> void:
	if _using_gamepad:
		_check_for_pointer(event)
	else:
		_check_for_gamepad(event)


func _check_for_gamepad(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventJoypadButton and event.pressed:
		pressed = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		pressed = true
	if not pressed:
		return
	_using_gamepad = true
	if _warp_allowed:
		_last_mouse_pos = get_viewport().get_mouse_position()
		get_viewport().warp_mouse(WARP_POS)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_skip_mouse_frames = 2
	_apply_pad_focusables()
	gamepad_detected.emit()
	refocus()


func _check_for_pointer(event: InputEvent) -> void:
	var pointer := false
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		pointer = true
	elif event is InputEventMouseButton and event.pressed:
		pointer = true
	elif event is InputEventMouseMotion and _skip_mouse_frames == 0:
		var motion := event as InputEventMouseMotion
		if motion.velocity.length_squared() > MOUSE_VELOCITY_SQ_MIN \
				and motion.relative.length_squared() <= MOUSE_RELATIVE_SQ_MAX:
			pointer = true
	if not pointer:
		return
	_using_gamepad = false
	if _warp_allowed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not (event is InputEventMouseMotion):
			get_viewport().warp_mouse(_last_mouse_pos)
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
	_apply_pad_focusables()
	pointer_detected.emit()


## Registers a control that should be reachable by controller navigation but
## must never show a focus ring for mouse/touch users (the reason its call
## site originally forced FOCUS_NONE): focus_mode flips with the input mode.
func make_pad_focusable(control: Control) -> void:
	control.focus_mode = Control.FOCUS_ALL if _using_gamepad else Control.FOCUS_NONE
	_pad_focusables.append(weakref(control))


func _apply_pad_focusables() -> void:
	var mode := Control.FOCUS_ALL if _using_gamepad else Control.FOCUS_NONE
	for i in range(_pad_focusables.size() - 1, -1, -1):
		var control: Variant = _pad_focusables[i].get_ref()
		if control == null or not is_instance_valid(control):
			_pad_focusables.remove_at(i)
			continue
		(control as Control).focus_mode = mode


## Registers/raises a focus context. provider is called (deferred) whenever
## this context should take focus and must return a Control or null.
func push_focus_context(context_owner: Node, provider: Callable) -> void:
	pop_focus_context(context_owner)
	_focus_stack.append({"owner": context_owner, "provider": provider})
	refocus()


func pop_focus_context(context_owner: Node) -> void:
	var was_top := is_top_context(context_owner)
	for i in range(_focus_stack.size() - 1, -1, -1):
		if _focus_stack[i]["owner"] == context_owner:
			_focus_stack.remove_at(i)
	if was_top:
		refocus()


func is_top_context(context_owner: Node) -> bool:
	_prune_focus_stack()
	if _focus_stack.is_empty():
		return false
	return _focus_stack[-1]["owner"] == context_owner


## Focuses the top context's default control — only in gamepad mode, so mouse
## and touch users never see a focus ring appear on its own.
func refocus() -> void:
	_do_refocus.call_deferred()


func _do_refocus() -> void:
	if not _using_gamepad:
		return
	_prune_focus_stack()
	if _focus_stack.is_empty():
		return
	var provider: Callable = _focus_stack[-1]["provider"]
	if not provider.is_valid():
		return
	var target: Variant = provider.call()
	if target is Control:
		var control := target as Control
		if control.is_inside_tree() and control.is_visible_in_tree() \
				and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()


func _prune_focus_stack() -> void:
	for i in range(_focus_stack.size() - 1, -1, -1):
		var context_owner: Variant = _focus_stack[i]["owner"]
		if not is_instance_valid(context_owner) \
				or (context_owner is Node and not (context_owner as Node).is_inside_tree()):
			_focus_stack.remove_at(i)
