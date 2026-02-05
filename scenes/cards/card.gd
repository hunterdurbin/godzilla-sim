extends Control

## Card node with hover scaling, drag functionality, and TCG card data display

# Signals
signal drag_started()
signal drag_ended()
signal card_clicked(card: Control)

# Card properties
@export var card_name: String = "Card Name"
@export var card_description: String = "Card description goes here."
@export var hover_scale: float = 1.15
@export var hover_lift: float = 40.0
@export var scale_duration: float = 0.2

# Card data
var card_data: Dictionary = {}
var is_face_down: bool = false
var is_selectable: bool = false

# Drag state
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO
var original_scale: Vector2 = Vector2.ONE
var drag_enabled: bool = true

# Tween reference
var tween: Tween
var _pre_hover_z_index: int = 0
var _pre_hover_position: Vector2 = Vector2.ZERO


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
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_selectable:
					card_clicked.emit(self)
					return
				if not drag_enabled:
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
				z_index = 0
				drag_ended.emit()

	elif event is InputEventMouseMotion and is_dragging:
		var new_position = get_global_mouse_position() - drag_offset
		var viewport_size = get_viewport_rect().size
		var card_size = size * scale

		new_position.x = clamp(new_position.x, 0, viewport_size.x - card_size.x)
		new_position.y = clamp(new_position.y, 0, viewport_size.y - card_size.y)

		global_position = new_position


func _on_mouse_entered() -> void:
	if not is_dragging:
		_pre_hover_z_index = z_index
		_pre_hover_position = position
		z_index = 50
		_animate_hover(true)


func _on_mouse_exited() -> void:
	if not is_dragging:
		z_index = _pre_hover_z_index
		_animate_hover(false)


func _animate_hover(entering: bool) -> void:
	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	if entering:
		tween.tween_property(self, "scale", original_scale * hover_scale, scale_duration)
		tween.tween_property(self, "position", _pre_hover_position + Vector2(0, -hover_lift), scale_duration)
	else:
		tween.tween_property(self, "scale", original_scale, scale_duration)
		tween.tween_property(self, "position", _pre_hover_position, scale_duration)


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
	z_index = 0

	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(self, "position", target_pos, duration)
	tween.tween_property(self, "scale", original_scale, duration)


func _update_display() -> void:
	if not is_node_ready():
		return

	var card_back = get_node_or_null("CardBack")
	var card_content = get_node_or_null("CardContent")

	if is_face_down:
		if card_back:
			card_back.visible = true
		if card_content:
			card_content.visible = false
		return

	if card_back:
		card_back.visible = false
	if card_content:
		card_content.visible = true

	# Title
	var title_label = get_node_or_null("CardContent/HeaderRow/Title")
	if not title_label:
		title_label = get_node_or_null("CardContent/Title")
	if title_label:
		title_label.text = card_name

	# Rank label
	var rank_label = get_node_or_null("CardContent/HeaderRow/RankLabel")
	if rank_label and not card_data.is_empty():
		var card_type = card_data.get("card_type", -1)
		var rank = card_data.get("rank", 0)
		if card_type == CardEnums.CardType.MONSTER:
			rank_label.text = CardEnums.rank_to_roman(rank)
		else:
			rank_label.text = str(rank)

	# Artwork color based on card color
	var artwork = get_node_or_null("CardContent/Artwork")
	if artwork and not card_data.is_empty():
		var color_enum = card_data.get("color", CardEnums.CardColor.WHITE)
		artwork.color = CardEnums.color_to_godot_color(color_enum)

	# Stats row
	var counter_label = get_node_or_null("CardContent/StatsRow/CounterLabel")
	if counter_label and not card_data.is_empty():
		var card_type = card_data.get("card_type", -1)
		match card_type:
			CardEnums.CardType.MONSTER:
				counter_label.text = "TL: %d" % card_data.get("threat_level", 0)
			CardEnums.CardType.BATTLE:
				counter_label.text = "CP: %d" % card_data.get("counter_power", 0)
			CardEnums.CardType.STRATEGY:
				counter_label.text = "Strategy"

	var invasion_label = get_node_or_null("CardContent/StatsRow/InvasionLabel")
	if invasion_label and not card_data.is_empty():
		var inv_icon = card_data.get("invasion_icon", 0)
		if inv_icon > 0:
			invasion_label.text = "Inv: %d" % inv_icon
		else:
			invasion_label.text = ""

	# Type label
	var type_label = get_node_or_null("CardContent/TypeLabel")
	if type_label and not card_data.is_empty():
		var card_type = card_data.get("card_type", -1)
		var trait_val = card_data.get("trait", -1)
		type_label.text = "%s - %s" % [
			CardEnums.type_to_string(card_type),
			CardEnums.trait_to_string(trait_val)
		]

	# Description
	var desc = get_node_or_null("CardContent/Description")
	if desc:
		desc.text = card_description
