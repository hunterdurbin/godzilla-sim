class_name DeckRow
extends Button
## One row in DeckListView: thumbnail of the highest-rank monster + deck name.

const _CardScript := preload("res://scenes/cards/card.gd")
const THUMB_SIZE := Vector2i(48, 48)
const THUMB_CROP_Y_RATIO := 0.08
const ROW_HEIGHT := 60
const ROW_HEIGHT_COMPACT := 26

signal selected(deck_name: String)
signal activated(deck_name: String)  ## Double-click / Enter
signal action_requested(deck_name: String, anchor_position: Vector2)  ## ⋯ button clicked

var deck_name: String = ""
var folder_path: String = ""
var _is_selected: bool = false
var _compact: bool = false

var _thumb_holder: Control
var _thumb: TextureRect
var _placeholder: Label
var _name_label: Label
var _actions_button: Button
var _last_click_time: int = -1


func _init() -> void:
	toggle_mode = false
	custom_minimum_size.y = ROW_HEIGHT
	flat = false
	GamepadHelper.make_pad_focusable(self)
	clip_text = true
	text = ""
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_selection_style()

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -8
	add_child(box)

	# Thumbnail container — fixed size, clips overflow
	_thumb_holder = Control.new()
	_thumb_holder.custom_minimum_size = Vector2(THUMB_SIZE.x, THUMB_SIZE.y)
	_thumb_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_thumb_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb_holder.clip_contents = true
	box.add_child(_thumb_holder)

	_placeholder = Label.new()
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.add_theme_font_size_override("font_size", 18)
	_placeholder.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3, 1))
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ph_style := StyleBoxFlat.new()
	ph_style.bg_color = Color(0.18, 0.10, 0.07, 1)
	ph_style.set_corner_radius_all(3)
	var ph_panel := PanelContainer.new()
	ph_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ph_panel.add_theme_stylebox_override("panel", ph_style)
	ph_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph_panel.add_child(_placeholder)
	_thumb_holder.add_child(ph_panel)

	_thumb = TextureRect.new()
	_thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.visible = false
	_thumb_holder.add_child(_thumb)

	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name_label)

	_actions_button = Button.new()
	_actions_button.text = "⋯"
	GamepadHelper.make_pad_focusable(_actions_button)
	_actions_button.custom_minimum_size = Vector2(32, 32)
	_actions_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_actions_button.visible = false
	_actions_button.pressed.connect(_on_actions_pressed)
	box.add_child(_actions_button)

	pressed.connect(_on_pressed)


func set_data(p_deck_name: String, p_folder: String, texture: Texture2D) -> void:
	deck_name = p_deck_name
	folder_path = p_folder
	_name_label.text = p_deck_name
	if texture != null:
		_thumb.texture = texture
		_thumb.visible = true
		_placeholder.text = ""
	else:
		_thumb.texture = null
		_thumb.visible = false
		_placeholder.text = p_deck_name.substr(0, 1).to_upper() if not p_deck_name.is_empty() else "?"


func set_selected(value: bool) -> void:
	if _is_selected == value:
		return
	_is_selected = value
	_apply_selection_style()


func set_dimmed(value: bool) -> void:
	## Visually grey the row without disabling it — used by DeckListView's format
	## filter to indicate decks not legal in the selected format. Row stays
	## clickable so the user can still inspect / edit / select it.
	modulate = Color(1, 1, 1, 0.45) if value else Color(1, 1, 1, 1)


func set_actions_visible(value: bool) -> void:
	if _actions_button != null:
		_actions_button.visible = value


func _on_actions_pressed() -> void:
	var anchor := _actions_button.global_position + Vector2(0, _actions_button.size.y)
	action_requested.emit(deck_name, anchor)


func set_compact_mode(value: bool) -> void:
	_compact = value
	if value:
		custom_minimum_size.y = ROW_HEIGHT_COMPACT
		_thumb_holder.visible = false
		_name_label.add_theme_font_size_override("font_size", 13)
		if _actions_button != null:
			_actions_button.custom_minimum_size = Vector2(28, 22)
			_actions_button.add_theme_font_size_override("font_size", 12)
	else:
		custom_minimum_size.y = ROW_HEIGHT
		_thumb_holder.visible = true
		_name_label.remove_theme_font_size_override("font_size")
		if _actions_button != null:
			_actions_button.custom_minimum_size = Vector2(32, 32)
			_actions_button.remove_theme_font_size_override("font_size")


func _apply_selection_style() -> void:
	if _is_selected:
		var sel := StyleBoxFlat.new()
		sel.bg_color = Color(0.30, 0.12, 0.05, 1)
		sel.border_color = Color(0.95, 0.45, 0.15, 1)
		sel.set_border_width_all(2)
		sel.set_corner_radius_all(3)
		add_theme_stylebox_override("normal", sel)
		add_theme_stylebox_override("hover", sel)
		add_theme_stylebox_override("pressed", sel)
		add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0)
		add_theme_stylebox_override("normal", bg)
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.20, 0.10, 0.06, 0.6)
		hover.set_corner_radius_all(3)
		add_theme_stylebox_override("hover", hover)
		var pressed_style := StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.25, 0.12, 0.07, 0.8)
		pressed_style.set_corner_radius_all(3)
		add_theme_stylebox_override("pressed", pressed_style)
		remove_theme_color_override("font_color")


func _on_pressed() -> void:
	var now := Time.get_ticks_msec()
	var is_double := _last_click_time >= 0 and (now - _last_click_time) < 300
	_last_click_time = now
	if is_double:
		activated.emit(deck_name)
	else:
		selected.emit(deck_name)


static func resolve_thumbnail_texture(card_id: String, cache: Dictionary) -> Texture2D:
	## Returns a square AtlasTexture cropped from the source artwork
	## (top edge offset by THUMB_CROP_Y_RATIO of source height).
	if card_id.is_empty():
		return null
	if cache.has(card_id):
		return cache[card_id]
	var set_number := card_id.split("-")[0]
	var path: String = _CardScript._find_artwork_path(set_number, card_id)
	if path.is_empty():
		cache[card_id] = null
		return null
	var img := Image.new()
	if img.load(path) != OK:
		cache[card_id] = null
		return null
	var base := ImageTexture.create_from_image(img)
	var w := img.get_width()
	var h := img.get_height()
	var side := mini(w, h)
	var y_offset := int(h * THUMB_CROP_Y_RATIO)
	if y_offset + side > h:
		y_offset = maxi(0, h - side)
	var atlas := AtlasTexture.new()
	atlas.atlas = base
	atlas.region = Rect2(0, y_offset, side, side)
	cache[card_id] = atlas
	return atlas
