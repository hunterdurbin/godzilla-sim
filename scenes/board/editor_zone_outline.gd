@tool
extends Control

## Editor-only visualization for placeholder info areas on PlayerBoard
## (DeckInfo, DiscardInfo, MonsterInfo). These are bare Controls filled with
## card stacks at runtime, so without this they are invisible in the editor.
## Draws nothing at runtime; must never mutate node properties in the editor.


func _ready() -> void:
	if Engine.is_editor_hint():
		resized.connect(queue_redraw)
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.8, 0.7, 0.3, 0.12), true)
	draw_rect(rect, Color(0.9, 0.8, 0.4, 0.7), false, 2.0)
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := 18
	var text := String(name)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2(
		(size.x - text_size.x) / 2.0,
		(size.y + font.get_ascent(font_size)) / 2.0 - font.get_descent(font_size) / 2.0
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.9))
