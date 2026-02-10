extends Control

## Card node with hover scaling, drag functionality, and TCG card image display

const ARTWORK_BASE_PATH := "user://CardContent/Artwork"

# Signals
signal drag_started()
signal drag_ended()
signal card_clicked(card: Control)
signal card_right_clicked(card: Control)
signal card_hover_started(card_ctrl: Control)
signal card_hover_ended(card_ctrl: Control)

# Card properties
@export var card_name: String = "Card Name"
@export var card_description: String = "Card description goes here."
@export var hover_scale: float = 1.15
@export var hover_scale_in_slot: float = 1.5
@export var hover_lift: float = 40.0
@export var invert_hover: bool = false  # When true, hover moves card down instead of up
@export var scale_duration: float = 0.2

# Card data
var card_data: Dictionary = {}
var card_effect: RefCounted = null  # CardEffect instance loaded from effect_script
var is_face_down: bool = false
var is_selectable: bool = false
var in_landscape_slot: bool = false

# Drag state
var is_dragging: bool = false
var is_snap_previewing: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO
var original_scale: Vector2 = Vector2.ONE
var drag_enabled: bool = true

# Tween reference
var tween: Tween
var _pre_hover_z_index: int = 0
var _pre_hover_position: Vector2 = Vector2.ZERO
var _hover_active: bool = false


func _ready() -> void:
	# Set up card content
	_update_display()

	# Store original values
	original_scale = scale
	original_position = position

	# Connect mouse signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not is_face_down:
				card_right_clicked.emit(self)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_selectable:
					card_clicked.emit(self)
					return
				if not drag_enabled or is_face_down:
					return
				# Start dragging
				is_dragging = true
				drag_offset = get_global_mouse_position() - global_position
				z_index = 100
				drag_started.emit()
			else:
				if not is_dragging:
					return
				# Stop dragging
				is_dragging = false
				is_snap_previewing = false
				_hover_active = false
				z_index = 0
				drag_ended.emit()

	elif event is InputEventMouseMotion and is_dragging:
		if is_snap_previewing:
			return
		var new_position = get_global_mouse_position() - drag_offset
		var viewport_size = get_viewport_rect().size
		var card_size = size * scale

		new_position.x = clamp(new_position.x, 0, viewport_size.x - card_size.x)
		new_position.y = clamp(new_position.y, 0, viewport_size.y - card_size.y)

		global_position = new_position


func _on_mouse_entered() -> void:
	if not is_dragging:
		if not _hover_active:
			_pre_hover_z_index = z_index
			# Only capture current position if no tween is running;
			# if a tween is active, _pre_hover_position already holds
			# the correct target set by return_to_position.
			if not tween or not tween.is_running():
				_pre_hover_position = position
		_hover_active = true
		z_index = 50
		_animate_hover(true)
	if not is_face_down and not card_data.is_empty():
		card_hover_started.emit(self)


func _on_mouse_exited() -> void:
	card_hover_ended.emit(self)
	if not is_dragging and _hover_active:
		z_index = _pre_hover_z_index
		_animate_hover(false)


func _is_in_slot() -> bool:
	return get_parent() is Slot


func _animate_hover(entering: bool) -> void:
	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	var in_slot := _is_in_slot()
	if entering:
		var target_hover_scale := hover_scale_in_slot if in_slot else hover_scale
		tween.tween_property(self, "scale", original_scale * target_hover_scale, scale_duration)
		if not in_slot:
			var lift_dir := 1.0 if invert_hover else -1.0
			tween.tween_property(self, "position", _pre_hover_position + Vector2(0, lift_dir * hover_lift), scale_duration)
	else:
		tween.tween_property(self, "scale", original_scale, scale_duration)
		if not in_slot:
			tween.tween_property(self, "position", _pre_hover_position, scale_duration)
		tween.chain().tween_callback(func(): _hover_active = false)


func _scale_card(target_scale: float) -> void:
	if tween:
		tween.kill()

	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "scale", original_scale * target_scale, scale_duration)


## Set card data from a dictionary (TCG format)
func set_card_data_dict(data: Dictionary) -> void:
	card_data = data
	card_name = data.get("name", "Unknown")
	card_description = data.get("description", "")
	# Load effect script if specified
	var script_path: String = data.get("effect_script", "")
	if not script_path.is_empty() and ResourceLoader.exists(script_path):
		var effect_script: GDScript = load(script_path)
		if effect_script:
			card_effect = effect_script.new()
	if is_node_ready():
		_update_display()


## Set basic card display data (legacy compatibility)
func set_card_data(title: String, description: String) -> void:
	card_name = title
	card_description = description
	if is_node_ready():
		_update_display()


## Toggle face-down state
func set_face_down(face_down: bool) -> void:
	is_face_down = face_down
	if is_node_ready():
		_update_display()


func return_to_position(target_pos: Vector2, duration: float = 0.3) -> void:
	if tween:
		tween.kill()

	is_dragging = false
	_hover_active = false
	_pre_hover_position = target_pos

	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(self, "position", target_pos, duration)
	tween.tween_property(self, "scale", original_scale, duration)


func start_snap_preview(target_pos: Vector2, target_scale: Vector2) -> void:
	is_snap_previewing = true
	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target_pos, 0.15)
	tween.tween_property(self, "scale", target_scale, 0.15)


func end_snap_preview() -> void:
	is_snap_previewing = false
	if tween:
		tween.kill()
	scale = original_scale


func _update_display() -> void:
	if not is_node_ready():
		return

	var card_back = get_node_or_null("CardBack")
	var card_image = get_node_or_null("CardImage")

	if is_face_down:
		if card_back:
			card_back.visible = true
		if card_image:
			card_image.visible = false
		return

	if card_back:
		card_back.visible = false
	if card_image:
		card_image.visible = true

	if card_image and not card_data.is_empty():
		var card_number := _resolve_card_number()
		if card_number.is_empty():
			return
		var set_number := card_number.split("-")[0]
		var image_path := ARTWORK_BASE_PATH.path_join(set_number).path_join("%s.png" % card_number)
		var abs_path := ProjectSettings.globalize_path(image_path)
		if FileAccess.file_exists(image_path):
			var image := Image.load_from_file(abs_path)
			if image:
				if _is_strategy_card():
					image.rotate_90(CLOCKWISE)
				card_image.texture = ImageTexture.create_from_image(image)


func _is_strategy_card() -> bool:
	var card_type = card_data.get("card_type", -1)
	if card_type == CardEnums.CardType.STRATEGY:
		return true
	var type_str: String = card_data.get("type", "")
	return type_str.to_lower() == "strategy"


## Resolve the card number from card_data, checking card_number then id.
## Strips deck/copy suffixes like "ESD01-008_0_1" -> "ESD01-008".
func _resolve_card_number() -> String:
	var card_number: String = card_data.get("card_number", "")
	if not card_number.is_empty():
		return card_number
	var id: String = card_data.get("id", "")
	if id.is_empty():
		return ""
	# Strip deck/copy suffix: "ESD01-008_0_1" -> "ESD01-008"
	var underscore_pos := id.find("_")
	if underscore_pos != -1:
		id = id.substr(0, underscore_pos)
	return id
