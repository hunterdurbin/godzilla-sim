@tool
class_name ControllerGlyph
extends TextureRect
## Scene-embedded gamepad button glyph (WYSIWYG).
##
## Drop one into any scene next to the button it annotates, set `action`, and
## the editor immediately previews the real glyph texture — flip
## `preview_type` to sanity-check all four controller art sets without
## running the game. At runtime the glyph textures itself from the live
## binding (GamepadInput) and is visible only while the gamepad is the
## active device (GamepadHelper), refreshing automatically on device switch,
## controller-type change, and rebind.
##
## For runtime-built UI (mobile FABs, options modals) construct via
## ControllerGlyph.new() and set `action` in code — same behavior.

const DEFAULT_SIZE := Vector2(28.0, 28.0)

## Logical pad_* action this glyph shows the binding for.
@export var action: StringName = &"pad_confirm":
	set(value):
		action = value
		_refresh()

## Editor-only: which controller art set to preview.
@export_enum("xbox", "playstation", "switch", "generic") var preview_type: String = "xbox":
	set(value):
		preview_type = value
		_refresh()

## Keep the glyph visible in pointer mode too (e.g. rebind UI rows).
@export var always_visible := false:
	set(value):
		always_visible = value
		_refresh()


func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = DEFAULT_SIZE


var _parent_button: BaseButton = null


func _ready() -> void:
	_refresh()
	if Engine.is_editor_hint():
		set_process(false)
		return
	GamepadHelper.gamepad_detected.connect(_refresh)
	GamepadHelper.pointer_detected.connect(_refresh)
	GamepadInput.input_rebound.connect(_refresh)
	GamepadInput.controller_type_changed.connect(_on_type_changed)
	# Glyphs on buttons track the button's disabled state (BaseButton has no
	# signal for it, so poll — a boolean compare per frame per glyph).
	_parent_button = get_parent() as BaseButton
	set_process(_parent_button != null)


func _process(_delta: float) -> void:
	var want := _should_show()
	if visible != want:
		visible = want


func _refresh() -> void:
	if Engine.is_editor_hint():
		var physical: StringName = GlyphDB.default_map().get(action, &"")
		if physical == &"":
			physical = _editor_nav_physical()
		texture = GlyphDB.get_texture(preview_type, physical)
		visible = true
		return
	if not is_inside_tree():
		return
	texture = GamepadInput.get_glyph(action)
	visible = _should_show()


func _should_show() -> bool:
	if _parent_button and _parent_button.disabled:
		return false
	return always_visible or GamepadHelper.is_using_gamepad()


func _on_type_changed(_type: String) -> void:
	_refresh()


## Editor preview for the fixed (non-rebindable) nav actions.
func _editor_nav_physical() -> StringName:
	match action:
		&"pad_nav_up": return &"controller_dpad_up"
		&"pad_nav_down": return &"controller_dpad_down"
		&"pad_nav_left": return &"controller_dpad_left"
		&"pad_nav_right": return &"controller_dpad_right"
	return &""
