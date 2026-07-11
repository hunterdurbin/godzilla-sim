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
## Emitted whenever the focus-context stack actually changes (push or pop).
## Lets the board nav suspend/restore its cursor when a modal takes over.
signal context_stack_changed

## Spire's mouse-motion guard: deliberate movement only (velocity² > 100),
## and not the huge relative jump produced by our own off-screen warp.
const MOUSE_VELOCITY_SQ_MIN := 100.0
const MOUSE_RELATIVE_SQ_MAX := 250000.0
const WARP_POS := Vector2(-1000.0, -1000.0)

var _using_gamepad := false
var _last_mouse_pos := Vector2.ZERO
var _skip_mouse_frames := 0
## LIFO of {"owner": Node, "provider": Callable, "return_focus": WeakRef|null}
## — provider returns the Control to focus (or null); return_focus remembers
## what held focus when the context was pushed, restored on pop.
var _focus_stack: Array[Dictionary] = []
## One-shot pop-restore target for the next _do_refocus (WeakRef or null).
var _return_focus: Variant = null
## Controls registered via make_pad_focusable: FOCUS_ALL only in gamepad
## mode, FOCUS_NONE otherwise (so mouse clicks never leave a focus ring).
var _pad_focusables: Array[WeakRef] = []
@onready var _warp_allowed: bool = OS.get_name() in ["Windows", "macOS", "Linux"] \
		and not DisplayServer.is_touchscreen_available()


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_root_gui_focus_changed)


## Pad navigation LANDING on a text field must not start editing (Godot 4
## enters edit mode with the focus grab): passing through a field would pop
## the platform's virtual keyboard and turn the next dpad press into an
## editing escape instead of a move. Only meshed fields (focus_neighbor
## wired — i.e. deliberately pad-navigable, like the deck builder's) are
## kept idle; unmeshed fields (board chat, dialog inputs) keep the
## focus-means-typing behavior. A starts editing deliberately (GamepadInput).
func _on_root_gui_focus_changed(control: Control) -> void:
	if _using_gamepad and control is LineEdit and has_focus_neighbors(control):
		(control as LineEdit).unedit.call_deferred()


## Whether any focus_neighbor is wired — the mark of a control that belongs
## to a wire_band_stack / focus mesh.
func has_focus_neighbors(control: Control) -> bool:
	return control.focus_neighbor_left != NodePath("") \
			or control.focus_neighbor_right != NodePath("") \
			or control.focus_neighbor_top != NodePath("") \
			or control.focus_neighbor_bottom != NodePath("")


func is_using_gamepad() -> bool:
	return _using_gamepad


func _process(_delta: float) -> void:
	if _skip_mouse_frames > 0:
		_skip_mouse_frames -= 1


func _input(event: InputEvent) -> void:
	# Twins of a cancel press that already closed something die here before
	# they can reach the surface the close uncovered (see swallow_cancel_twins).
	if is_swallowed_cancel(event):
		get_viewport().set_input_as_handled()
		return
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
	# A mouse click may have left real focus behind (the pointer flip releases
	# BEFORE the click lands on its button), and the null-provider contexts
	# (the board) never re-grab — the mirrored ui_* events would then drive a
	# second focus ring next to the controller cursor. Release it; refocus()
	# re-grabs the right control for provider-backed contexts.
	var focus_owner := gui_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
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
	var focus_owner := gui_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
	_apply_pad_focusables()
	pointer_detected.emit()


const _MODAL_META := &"_gamepad_modal"

## One physical B press produces up to three events: the raw joypad event
## plus the pad_cancel and mirrored ui_cancel twins GamepadInput injects. A
## handler that acts on the LEADING press stamps this frame; the remaining
## twins are then swallowed — in _input for root-stage events, and via
## is_swallowed_cancel checks inside cancel handlers — so they can't leak
## into whatever the close uncovered (e.g. a screen's B-back handler right
## under a closed dialog).
var _cancel_swallow_frame: int = -100


func swallow_cancel_twins() -> void:
	_cancel_swallow_frame = Engine.get_process_frames()


func is_swallowed_cancel(event: InputEvent) -> bool:
	if Engine.get_process_frames() - _cancel_swallow_frame > 2:
		return false
	return is_cancel_press(event)


## Any face of one B press: the injected pad_cancel, its mirrored ui_cancel
## (also matches keyboard ESC), or the raw physical button pad_cancel is
## currently bound to.
func is_cancel_press(event: InputEvent) -> bool:
	if event.is_action_pressed("pad_cancel") or event.is_action_pressed("ui_cancel"):
		return true
	var physical: StringName = GamepadInput.get_physical(&"pad_cancel")
	return physical != &"" and event.is_action_pressed(physical)


## Pad B / keyboard ESC closes an embedded popup Window. Reacts to the
## LEADING cancel press — the raw physical button works even where injected
## twins misroute, which is why this must not wait for the trailing ui_cancel
## mirror — and swallows the twins that follow. `on_close` replaces the
## default hide() when the popup's Cancel carries extra teardown.
func wire_pad_close(popup: Window, on_close := Callable()) -> void:
	popup.window_input.connect(func(event: InputEvent) -> void:
		if not is_cancel_press(event):
			return
		popup.set_input_as_handled()
		if is_swallowed_cancel(event) or not popup.visible:
			return  # a twin of the press that already closed it
		if GamepadInput._is_text_editing():
			return  # B escapes the editing text field, not the dialog
		swallow_cancel_twins()
		if on_close.is_valid():
			on_close.call()
		else:
			popup.hide()
	)


## One-liner modal registration: pushes a focus context while `surface` is
## visible and pops it on hide and on free. `surface` may be a Window
## (ConfirmationDialog/AcceptDialog/PopupPanel/PopupMenu — all embedded
## subwindows in this project) or an in-canvas Control prompt. Idempotent;
## callable before or after the surface is first shown. With no provider, a
## sensible default button is resolved lazily at push time.
func register_modal(surface: Node, provider := Callable()) -> void:
	if surface.has_meta(_MODAL_META):
		return
	surface.set_meta(_MODAL_META, true)
	var resolved := provider if provider.is_valid() else _default_modal_provider(surface)
	surface.visibility_changed.connect(_on_modal_visibility.bind(surface, resolved))
	surface.tree_exiting.connect(pop_focus_context.bind(surface))
	if surface is Window:
		# A focused embedded Window swallows input BEFORE the root viewport's
		# _input/_unhandled_input stages (Viewport forwards to the focused
		# subwindow first), starving the device-mode tracker and the pad
		# translator — buttons would be dead inside every dialog. Re-run both
		# on events surfacing inside the window.
		(surface as Window).window_input.connect(_on_modal_window_input)
		# The LineEdit unedit fence (_ready) only watches the ROOT viewport's
		# gui_focus_changed; an embedded Window is its own viewport, so pad
		# navigation landing on a meshed LineEdit inside a dialog would start
		# editing. Watch the dialog's focus changes too.
		(surface as Window).gui_focus_changed.connect(_on_root_gui_focus_changed)
	if _modal_visible(surface):
		push_focus_context(surface, resolved)


func _on_modal_window_input(event: InputEvent) -> void:
	# Same order as the root pipeline: device-mode check (_input), then the
	# pad translation (_unhandled_input). The injected pad_*/ui_* twins are
	# routed back to the focused window by the same subwindow forwarding, so
	# the dialog's focused button and its close-on-cancel keep working.
	_input(event)
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		GamepadInput.translate_event(event)


func _on_modal_visibility(surface: Node, provider: Callable) -> void:
	if _modal_visible(surface):
		push_focus_context(surface, provider)
	else:
		pop_focus_context(surface)


func _modal_visible(surface: Node) -> bool:
	if surface is Window:
		return (surface as Window).visible
	if surface is Control:
		return (surface as Control).is_visible_in_tree()
	return false


func _default_modal_provider(surface: Node) -> Callable:
	# Destructive confirms (leave game, delete deck, ...) must not put A on
	# the destructive action — land on Cancel; dpad reaches OK, B closes.
	if surface is ConfirmationDialog:
		return func() -> Control: return (surface as ConfirmationDialog).get_cancel_button()
	if surface is AcceptDialog:
		return func() -> Control:
			var ok := (surface as AcceptDialog).get_ok_button()
			return ok if ok.visible else find_first_focusable(surface)
	if surface is PopupMenu:
		# PopupMenu navigates its items internally once its window has focus;
		# grabbing a Control would fight it. The context push still suspends
		# the layer beneath and refocuses it on close.
		return func() -> Control: return null
	return find_first_focusable.bind(surface)


## Depth-first first visible focusable control under root.
func find_first_focusable(root: Node) -> Control:
	if root is Control:
		var control := root as Control
		if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			return control
	for child in root.get_children():
		var found := find_first_focusable(child)
		if found != null:
			return found
	return null


## Focus owner that sees inside embedded dialog Windows: each embedded
## Window is its own Viewport, so the root viewport's gui_get_focus_owner()
## returns null while a dialog child (e.g. a rename LineEdit) is focused.
func gui_focus_owner() -> Control:
	_prune_focus_stack()
	if not _focus_stack.is_empty():
		var top_owner: Variant = _focus_stack[-1]["owner"]
		if top_owner is Window and (top_owner as Window).visible:
			return (top_owner as Window).gui_get_focus_owner()
	return get_viewport().gui_get_focus_owner()


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
## this context should take focus and must return a Control or null. The
## control focused at push time is remembered: popping the context restores
## it (modal closed → cursor back on the button that opened it) and only
## falls back to the uncovered top's provider when the remembered control is
## gone, hidden, or no longer focusable (e.g. a rebuilt grid wrapper).
func push_focus_context(context_owner: Node, provider: Callable) -> void:
	_remove_context(context_owner)
	var below := gui_focus_owner()
	_focus_stack.append({
		"owner": context_owner,
		"provider": provider,
		"return_focus": weakref(below) if below != null else null,
	})
	_return_focus = null  # the new context owns focus; any pending restore is stale
	refocus()
	context_stack_changed.emit()


func pop_focus_context(context_owner: Node) -> void:
	var was_top := is_top_context(context_owner)
	var return_focus: Variant = _return_focus_of(context_owner)
	if not _remove_context(context_owner):
		return # Idempotent pop (e.g. tree_exiting after hide): no change, no emit.
	if was_top:
		_return_focus = return_focus
		refocus()
	context_stack_changed.emit()


func _return_focus_of(context_owner: Node) -> Variant:
	for i in range(_focus_stack.size() - 1, -1, -1):
		if _focus_stack[i]["owner"] == context_owner:
			return _focus_stack[i].get("return_focus")
	return null


func _remove_context(context_owner: Node) -> bool:
	var removed := false
	for i in range(_focus_stack.size() - 1, -1, -1):
		if _focus_stack[i]["owner"] == context_owner:
			_focus_stack.remove_at(i)
			removed = true
	return removed


func is_top_context(context_owner: Node) -> bool:
	_prune_focus_stack()
	if _focus_stack.is_empty():
		return false
	return _focus_stack[-1]["owner"] == context_owner


## Focuses the top context's default control — only in gamepad mode, so mouse
## and touch users never see a focus ring appear on its own. A pop-restore
## target set by pop_focus_context wins over the provider for one refocus.
func refocus() -> void:
	_do_refocus.call_deferred()


func _do_refocus() -> void:
	var pending: Variant = _return_focus
	_return_focus = null  # one shot — consumed (or discarded) right here
	if not _using_gamepad:
		return
	_prune_focus_stack()
	if _focus_stack.is_empty():
		return
	if pending is WeakRef:
		var remembered: Variant = (pending as WeakRef).get_ref()
		if remembered is Control and _can_grab_focus(remembered):
			(remembered as Control).grab_focus()
			return
	var provider: Callable = _focus_stack[-1]["provider"]
	if not provider.is_valid():
		return
	var target: Variant = provider.call()
	if target is Control and _can_grab_focus(target):
		(target as Control).grab_focus()


func _can_grab_focus(control: Control) -> bool:
	return control.is_inside_tree() and control.is_visible_in_tree() \
			and control.focus_mode != Control.FOCUS_NONE


func _prune_focus_stack() -> void:
	for i in range(_focus_stack.size() - 1, -1, -1):
		var context_owner: Variant = _focus_stack[i]["owner"]
		if not is_instance_valid(context_owner) \
				or (context_owner is Node and not (context_owner as Node).is_inside_tree()):
			_focus_stack.remove_at(i)
