class_name PlayerBoardHelpers

## Static utility helpers for PlayerBoard's runtime widget construction.
## Pulled out of `player_board.gd` to make the visual-construction code
## easier to find, reuse, and (eventually) replace with Node-based
## components. Designers building a custom PlayerBoard variant can
## bypass these by setting `enable_deck_stack=false` /
## `enable_info_borders=false` on the board, or by populating the
## `*_count_badge` @export slots with editor-placed Labels.
##
## All methods are stateless — caller passes the relevant config as
## arguments. Texture loading + per-instance state (custom card back,
## player_id-aware logic) stays in `player_board.gd`.


## Build the count Label that overlays a deck/discard/monster-info
## zone. Returns the unparented Label — caller adds it as a child of
## the target Control.
static func create_count_badge(
	font_size: int,
	color: Color,
	outline_color: Color,
	outline_size: int
) -> Label:
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", font_size)
	badge.add_theme_color_override("font_color", color)
	badge.add_theme_color_override("font_outline_color", outline_color)
	badge.add_theme_constant_override("outline_size", outline_size)
	badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	badge.offset_top = -24
	badge.offset_bottom = 0
	badge.offset_left = -20
	badge.offset_right = 20
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	return badge


## Build a single card-back Panel (StyleBoxFlat background + a
## TextureRect with the card-back texture, full-rect anchored). Used
## as one layer in a deck-stack visualization.
static func create_card_back_panel(card_back_texture: Texture2D) -> Panel:
	var panel := Panel.new()
	panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.24, 1)
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.4, 0.5, 1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex_rect := TextureRect.new()
	tex_rect.texture = card_back_texture
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tex_rect)
	return panel


## Create N card-back panels under `parent`, each shifted upward by
## `layer_shift` pixels from the previous. Caller appends them to its
## own tracking array (`stack_arr`) so the visible-count update logic
## can show/hide layers as the deck grows or shrinks.
static func create_deck_stack(
	parent: Control,
	stack_arr: Array[Control],
	max_layers: int,
	layer_shift: float,
	card_back_texture: Texture2D
) -> void:
	for i in range(max_layers):
		var panel := create_card_back_panel(card_back_texture)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var shift := float(i) * layer_shift
		panel.offset_top = -shift
		panel.offset_bottom = -shift
		panel.visible = false
		parent.add_child(panel)
		stack_arr.append(panel)


## Connect a draw callback to `control` that paints a 1px border at
## the configured color/width, redrawing on resize. Idempotent: safe
## to call once per control, but don't call twice on the same
## control or you'll get a double-painted border.
static func add_border(control: Control, color: Color, width: float) -> void:
	var draw_callback := func():
		var rect := Rect2(Vector2.ZERO, control.size)
		control.draw_rect(rect, color, false, width)
	control.draw.connect(draw_callback)
	control.resized.connect(control.queue_redraw)
	control.queue_redraw()


## Set a fully-transparent StyleBoxFlat on a rage-zone Panel. The
## designer can replace this in the editor with their own StyleBox;
## this is the legacy "no visible background" treatment.
static func style_rage_bg(rage_bg_panel: Panel) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.3, 0.0)
	style.border_color = Color(1, 1, 1, 0.0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	rage_bg_panel.add_theme_stylebox_override("panel", style)


## Wire up a discard-zone Control: spawn an "empty" Label that shows
## when the discard pile is empty + parent the supplied `top_card`
## (already-instantiated Card scene) full-rect, set its mouse filter +
## drag flags so it doesn't interfere with hover/zone clicks. Returns
## the empty Label so the caller can show/hide it as the pile fills.
static func setup_discard_zone(
	parent: Control,
	top_card: Control,
	empty_label_text: String
) -> Label:
	var empty := Label.new()
	empty.text = empty_label_text
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty.add_theme_font_size_override("font_size", 9)
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(empty)
	if "drag_enabled" in top_card:
		top_card.drag_enabled = false
	top_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_card.custom_minimum_size = Vector2.ZERO
	top_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_card.visible = false
	parent.add_child(top_card)
	var bg := top_card.get_node_or_null("Background") as Control
	if bg:
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return empty
