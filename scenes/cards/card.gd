extends Control

## Card node with hover scaling and drag functionality

# Signals
signal drag_started()
signal drag_ended()

# Card properties
@export var card_name: String = "Card Name"
@export var card_description: String = "Card description goes here."
@export var hover_scale: float = 1.15
@export var scale_duration: float = 0.2

# Drag state
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO
var original_scale: Vector2 = Vector2.ONE

# Tween reference
var tween: Tween


func _ready() -> void:
	# Set up card content
	$CardContent/Title.text = card_name
	$CardContent/Description.text = card_description

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
				# Start dragging
				is_dragging = true
				drag_offset = get_global_mouse_position() - global_position
				# Bring card to front
				z_index = 100
				drag_started.emit()
			else:
				# Stop dragging
				is_dragging = false
				z_index = 0
				drag_ended.emit()

	elif event is InputEventMouseMotion and is_dragging:
		# Update position while dragging with screen bounds clamping
		var new_position = get_global_mouse_position() - drag_offset
		var viewport_size = get_viewport_rect().size
		var card_size = size * scale

		# Clamp position to keep card fully on screen
		new_position.x = clamp(new_position.x, 0, viewport_size.x - card_size.x)
		new_position.y = clamp(new_position.y, 0, viewport_size.y - card_size.y)

		global_position = new_position


func _on_mouse_entered() -> void:
	if not is_dragging:
		_scale_card(hover_scale)


func _on_mouse_exited() -> void:
	if not is_dragging:
		_scale_card(1.0)


func _scale_card(target_scale: float) -> void:
	# Kill existing tween if any
	if tween:
		tween.kill()

	# Create new tween for smooth scaling
	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "scale", original_scale * target_scale, scale_duration)


## Public methods for card manipulation

func set_card_data(title: String, description: String) -> void:
	"""Set the card's display data"""
	card_name = title
	card_description = description
	if is_node_ready():
		$CardContent/Title.text = card_name
		$CardContent/Description.text = card_description


func return_to_position(target_pos: Vector2, duration: float = 0.3) -> void:
	"""Animate the card returning to a specific position"""
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
