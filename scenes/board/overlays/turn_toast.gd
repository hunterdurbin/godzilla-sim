class_name TurnToast
extends Control

## Brief center-screen announcement shown on turn changes ("Your Turn",
## "{PLAYER}'s Turn"). Purely decorative: every node ignores mouse input and
## the whole control fades out and hides after ~1.6s.

var _label: Label
var _panel_style: StyleBoxFlat
var _tween: Tween


func _ready() -> void:
	visible = false
	z_index = 90 # above mobile FABs/trays (z 55-61), below prompt overlays (z 100)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	_panel_style.border_color = Color(0.85, 0.65, 0.2, 0.9)
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(6)
	_panel_style.content_margin_left = 28
	_panel_style.content_margin_right = 28
	_panel_style.content_margin_top = 12
	_panel_style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", _panel_style)
	center.add_child(panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Text arrives already translated/composed by the caller.
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	panel.add_child(_label)


func show_turn_toast(text: String) -> void:
	if _tween:
		_tween.kill()
	var color: Color = GameSettings.turn_indicator_color
	_label.add_theme_color_override("font_color", color)
	_panel_style.border_color = Color(color, 0.9)
	_label.text = text
	modulate.a = 0.0
	visible = true
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.15)
	_tween.tween_interval(1.1)
	_tween.tween_property(self, "modulate:a", 0.0, 0.35)
	_tween.tween_callback(func() -> void: visible = false)
