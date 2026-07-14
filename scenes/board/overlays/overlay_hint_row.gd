class_name OverlayHintRow
extends HBoxContainer

## Controller glyph+label hint cluster for the board overlays ("A Select ·
## Y Inspect · B Skip"). Visible only in gamepad mode and never on mobile —
## the same policy as HandHintBar; the labels don't self-hide the way
## ControllerGlyph does, so the row listens to the device signals and hides
## itself. Rebuild the contents with set_hints() whenever the legal actions
## change (e.g. a prompt becomes skippable).


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	GamepadHelper.gamepad_detected.connect(_refresh_visibility)
	GamepadHelper.pointer_detected.connect(_refresh_visibility)
	_refresh_visibility()


## hints: Array of {action: StringName, text: String} (text pre-translated);
## an optional "action2" adds a second glyph before the label (LB/RB pairs).
func set_hints(hints: Array[Dictionary]) -> void:
	for child in get_children():
		child.queue_free()
	for hint in hints:
		var glyph := ControllerGlyph.new()
		glyph.action = hint["action"]
		add_child(glyph)
		if hint.has("action2"):
			var glyph2 := ControllerGlyph.new()
			glyph2.action = hint["action2"]
			add_child(glyph2)
		var label := Label.new()
		label.text = hint["text"]
		label.add_theme_font_size_override("font_size", 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	_refresh_visibility()


func _refresh_visibility() -> void:
	visible = GamepadHelper.is_using_gamepad() \
			and not GameSettings.use_mobile_layout \
			and not TouchHelper.is_touch_device()
