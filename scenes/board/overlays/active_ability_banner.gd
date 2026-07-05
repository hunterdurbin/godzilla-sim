class_name ActiveAbilityBanner
extends Control

## Floating top-center banner shown above the effect prompt overlays while
## an ability is resolving: the source card's thumbnail (same crop as the
## resolution-order choice buttons) plus its location label, so the player
## always knows WHICH ability the modal belongs to.

var zoom_requested: Callable # Board's _show_card_zoom; wired like the router callbacks

var _panel: PanelContainer
var _thumb: TextureRect
var _label: Label
var _card_id: String = ""


func _ready() -> void:
	visible = false
	z_index = 110 # above the prompt overlays (z 100)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored strip at the top-center of the screen
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -300.0
	offset_right = 300.0
	offset_top = 6.0
	offset_bottom = 70.0

	_panel = PanelContainer.new()
	# Right-click zoom is handled in _input: the banner sits early in the
	# board's tree, so GUI picking (tree order, not z_index) would route
	# clicks to the board drawn beneath it instead of this panel.
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	style.border_color = Color(0.85, 0.65, 0.2, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_panel)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)

	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(48, 48)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_thumb)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# No overrun trimming: with TRIM_ELLIPSIS a Label's minimum width
	# collapses to ~0 and the size-hugging panel renders no text at all.
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label)


## Show the resolving ability: `card_id` is a base id ("EBP04-089"),
## `label` is the same summary used on resolution-order choice buttons
## (e.g. "Inherited Life (Strategy 1)"). Empty card_id hides the banner.
func show_ability(card_id: String, label: String) -> void:
	if card_id.is_empty() and label.is_empty():
		hide_banner()
		return
	_card_id = card_id
	_thumb.texture = OverlayGridUtil.get_choice_thumb(card_id)
	_thumb.visible = _thumb.texture != null
	_label.text = label
	visible = true


func hide_banner() -> void:
	visible = false
	_thumb.texture = null
	_label.text = ""
	_card_id = ""


## The banner draws above everything (z 110) but early tree order means GUI
## picking would never deliver events to it — so catch right-clicks on its
## rect here and stop them from reaching whatever sits underneath.
func _input(event: InputEvent) -> void:
	if not visible or _card_id.is_empty():
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		# make_input_local resolves the stretch/canvas transforms so the hit
		# test is right regardless of window scaling.
		var local_event: InputEvent = _panel.make_input_local(event)
		if Rect2(Vector2.ZERO, _panel.size).has_point(local_event.position):
			_request_zoom()
			get_viewport().set_input_as_handled()


## Enlarged card view for the resolving ability's source card.
func _request_zoom() -> void:
	if _card_id.is_empty() or not zoom_requested.is_valid():
		return
	var dict: Dictionary = CardData.get_card_by_id(_card_id)
	if dict.is_empty():
		return
	zoom_requested.call(dict.duplicate(true), 0)
