extends Node
## Translates physical controller_* actions into logical pad_* actions.
##
## Two-layer design (ported from Slay the Spire 2's NInputManager +
## GodotControllerInputStrategy): project.godot binds ONLY physical
## controller_* actions to joypad events; game code listens ONLY to logical
## pad_* actions, which this autoload injects via Input.parse_input_event.
## Rebinding is a dictionary swap here — no InputMap surgery — and glyphs key
## off logical actions, so a rebind updates every glyph through one signal.
##
## pad_confirm / pad_cancel / pad_nav_* are additionally mirrored onto
## ui_accept / ui_cancel / ui_up|down|left|right so Godot's built-in focus
## navigation and every existing ui_cancel handler work on a controller.
## (The [input] section redeclares those ui_* actions keyboard-only, so the
## mirror is the ONLY joypad path into them — no double-firing.)
##
## Registered as autoload "GamepadInput" in project.godot.

## Emitted after a rebind or reset; glyph displays refresh from it.
signal input_rebound
## Emitted when the detected controller type ("xbox"/"playstation"/...) changes.
signal controller_type_changed(type: String)

## Logical action -> mirrored built-in ui_* action.
const UI_MIRROR := {
	&"pad_confirm": &"ui_accept",
	&"pad_cancel": &"ui_cancel",
	&"pad_nav_up": &"ui_up",
	&"pad_nav_down": &"ui_down",
	&"pad_nav_left": &"ui_left",
	&"pad_nav_right": &"ui_right",
}

## Navigation is fixed (not rebindable): dpad and left stick.
const NAV_PHYSICAL := {
	&"controller_dpad_up": &"pad_nav_up",
	&"controller_dpad_down": &"pad_nav_down",
	&"controller_dpad_left": &"pad_nav_left",
	&"controller_dpad_right": &"pad_nav_right",
}
const STICK_PHYSICAL := {
	&"controller_lstick_up": &"pad_nav_up",
	&"controller_lstick_down": &"pad_nav_down",
	&"controller_lstick_left": &"pad_nav_left",
	&"controller_lstick_right": &"pad_nav_right",
}

## Joypad events never echo, so held-direction repeat is explicit.
const REPEAT_DELAY_SEC := 0.4
const REPEAT_INTERVAL_SEC := 0.12

var controller_type: String = "generic"

## Logical pad_* -> physical controller_* (rebindable subset only).
var _map: Dictionary = {}
## Held nav directions: physical StringName -> seconds held (for repeat).
var _nav_held: Dictionary = {}
## Rebind capture: while valid, the next capturable physical press calls this
## with the captured physical action instead of being translated.
var _capture_cb: Callable = Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_map = GlyphDB.default_map()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_detect_controller_type()


## Logical actions the rebind UI offers, in display order (navigation is
## fixed to dpad/stick and deliberately absent).
func get_rebindable_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(GlyphDB.default_map().keys())
	return out


func get_physical(logical: StringName) -> StringName:
	if _map.has(logical):
		return _map[logical]
	# Fixed nav actions map to the dpad for glyph purposes.
	for physical: StringName in NAV_PHYSICAL:
		if NAV_PHYSICAL[physical] == logical:
			return physical
	return &""


func get_glyph(logical: StringName) -> Texture2D:
	return GlyphDB.get_texture(controller_type, get_physical(logical))


func is_capturing() -> bool:
	return _capture_cb.is_valid()


## Rebind UI: the next capturable physical button press calls
## callback(physical: StringName) instead of firing its action.
## Keyboard ESC cancels (callback receives &"").
func begin_capture(callback: Callable) -> void:
	_capture_cb = callback


func cancel_capture() -> void:
	_capture_cb = Callable()


## Rebinds a logical action, swapping on conflict so two actions never share
## a button (port of spire's ModifyControllerButton).
func rebind(logical: StringName, physical: StringName) -> void:
	if not _map.has(logical) or not GlyphDB.FILE_FOR_PHYSICAL.has(physical):
		return
	var previous: StringName = _map[logical]
	for other: StringName in _map:
		if other != logical and _map[other] == physical:
			_map[other] = previous
	_map[logical] = physical
	_persist_bindings()
	input_rebound.emit()


func reset_to_defaults() -> void:
	_map = GlyphDB.default_map()
	GameSettings.controller_bindings = {}
	GameSettings.controller_mapping_type = controller_type
	GameSettings.save()
	input_rebound.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	_detect_controller_type()
	if _capture_cb.is_valid():
		_handle_capture(event)
		return
	# Rebindable actions.
	var text_editing := _is_text_editing()
	for logical: StringName in _map:
		var physical: StringName = _map[logical]
		if event.is_action_pressed(physical):
			if text_editing and logical != &"pad_cancel":
				continue
			_inject(logical, true)
		elif event.is_action_released(physical):
			_inject(logical, false)
	# Fixed dpad navigation (stick handled in _process).
	for physical: StringName in NAV_PHYSICAL:
		if event.is_action_pressed(physical):
			if not text_editing:
				_inject(NAV_PHYSICAL[physical], true)
			_nav_held[physical] = 0.0
		elif event.is_action_released(physical):
			_inject(NAV_PHYSICAL[physical], false)
			_nav_held.erase(physical)


func _input(event: InputEvent) -> void:
	# Keyboard ESC cancels rebind capture (runs in _input so the capture wins
	# over any other ESC handling while active).
	if _capture_cb.is_valid() and event is InputEventKey \
			and event.pressed and event.physical_keycode == KEY_ESCAPE:
		var cb := _capture_cb
		_capture_cb = Callable()
		cb.call(&"")
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _capture_cb.is_valid():
		return
	var text_editing := _is_text_editing()
	# Left stick -> nav actions (spire's GodotControllerInputStrategy).
	for physical: StringName in STICK_PHYSICAL:
		if Input.is_action_just_pressed(physical):
			if not text_editing:
				_inject(STICK_PHYSICAL[physical], true)
			_nav_held[physical] = 0.0
		elif Input.is_action_just_released(physical):
			_inject(STICK_PHYSICAL[physical], false)
			_nav_held.erase(physical)
	# Hold-repeat for held nav directions.
	if text_editing:
		return
	for physical: StringName in _nav_held:
		if not Input.is_action_pressed(physical):
			continue
		var held: float = _nav_held[physical] + delta
		if held >= REPEAT_DELAY_SEC + REPEAT_INTERVAL_SEC:
			held = REPEAT_DELAY_SEC
			var logical: StringName = NAV_PHYSICAL.get(physical, STICK_PHYSICAL.get(physical, &""))
			if logical != &"":
				_inject(logical, true)
		_nav_held[physical] = held


func _handle_capture(event: InputEvent) -> void:
	for physical: StringName in GlyphDB.REBIND_CAPTURABLE:
		if event.is_action_pressed(physical):
			var cb := _capture_cb
			_capture_cb = Callable()
			cb.call(physical)
			get_viewport().set_input_as_handled()
			return


func _inject(logical: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = logical
	ev.pressed = pressed
	Input.parse_input_event(ev)
	if UI_MIRROR.has(logical):
		var mirror := InputEventAction.new()
		mirror.action = UI_MIRROR[logical]
		mirror.pressed = pressed
		Input.parse_input_event(mirror)


## While a text field is being edited, only pad_cancel goes through (port of
## spire's NHotkeyManager LineEdit guard) so face buttons type, not act.
func _is_text_editing() -> bool:
	var owner_control := get_viewport().gui_get_focus_owner()
	if owner_control is LineEdit:
		return (owner_control as LineEdit).editable
	if owner_control is TextEdit:
		return (owner_control as TextEdit).editable
	return false


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_detect_controller_type()


func _detect_controller_type() -> void:
	var pads := Input.get_connected_joypads()
	var detected := "generic" if pads.is_empty() else GlyphDB.detect_type(Input.get_joy_name(pads[0]))
	if detected == controller_type:
		return
	controller_type = detected
	_load_bindings()
	controller_type_changed.emit(controller_type)
	input_rebound.emit()


## Saved bindings are per controller type (spire behavior): apply them only
## when they were saved for the currently detected type.
func _load_bindings() -> void:
	_map = GlyphDB.default_map()
	if GameSettings.controller_mapping_type != controller_type:
		return
	var saved: Dictionary = GameSettings.controller_bindings
	for key: Variant in saved:
		var logical := StringName(str(key))
		var physical := StringName(str(saved[key]))
		if _map.has(logical) and GlyphDB.FILE_FOR_PHYSICAL.has(physical):
			_map[logical] = physical


func _persist_bindings() -> void:
	var out := {}
	var defaults := GlyphDB.default_map()
	for logical: StringName in _map:
		if _map[logical] != defaults[logical]:
			out[String(logical)] = String(_map[logical])
	GameSettings.controller_bindings = out
	GameSettings.controller_mapping_type = controller_type
	GameSettings.save()
