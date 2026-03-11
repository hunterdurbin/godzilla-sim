extends Control

## Card node with hover scaling, drag functionality, and TCG card image display

const ARTWORK_BASE_PATH := "user://CardContent/Artwork"
const CARD_BACK_PATH := "res://assets/cardBacks/default.jpeg"

static var _custom_art_base: String = ""
static var _custom_card_back_base: String = ""


static func _get_custom_art_base() -> String:
	if _custom_art_base.is_empty():
		_custom_art_base = GameSettings.get_custom_base_path().path_join("cardArt")
	return _custom_art_base


static func _get_custom_card_back_base() -> String:
	if _custom_card_back_base.is_empty():
		_custom_card_back_base = GameSettings.get_custom_base_path().path_join("cardBack")
	return _custom_card_back_base


## Case-insensitive file search for custom art (iOS filesystem is case-sensitive).
static func _find_custom_file(dir_path: String, card_number: String) -> String:
	var da := DirAccess.open(dir_path)
	if da == null:
		return ""
	var prefix := card_number.to_lower() + "."
	da.list_dir_begin()
	var file_name := da.get_next()
	while not file_name.is_empty():
		if not da.current_is_dir() and file_name.to_lower().begins_with(prefix):
			return dir_path.path_join(file_name)
		file_name = da.get_next()
	return ""

# Static texture cache shared across all Card instances
static var _texture_cache: Dictionary = {}  # card_number -> ImageTexture
static var _strategy_texture_cache: Dictionary = {}  # card_number -> ImageTexture (rotated)
static var _custom_texture_cache: Dictionary = {}  # card_number -> ImageTexture (custom art)
static var _custom_strategy_texture_cache: Dictionary = {}  # card_number -> ImageTexture (custom rotated)
static var _default_card_back_texture: Texture2D = null
static var _custom_card_back_texture: Texture2D = null  # null means no custom file found
static var _card_back_loaded: bool = false

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
var click_on_release: bool = false  # When true, defer card_clicked to mouse release with deadzone
var in_landscape_slot: bool = false
var use_custom_art: bool = true
var skip_effect_load: bool = false  # Skip loading effect scripts (e.g. in deck builder)
var owner_player_id: int = -1  # -1 = unset (shows custom art), 0/1 = player ID

# Drag state
var is_dragging: bool = false
var is_snap_previewing: bool = false
var is_locked_in_zone: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO
var original_scale: Vector2 = Vector2.ONE
var drag_enabled: bool = true

# Tween reference
var tween: Tween
var _pre_hover_z_index: int = 0
var _pre_hover_position: Vector2 = Vector2.ZERO
var _hover_active: bool = false

# Desktop click-on-release state
var _mouse_press_start_pos: Vector2 = Vector2.ZERO

# Double-click tracking (per-card: only double-click if same card clicked twice)
static var _last_clicked_card: Control = null

# Touch drag state (active only on touch devices)
var _touch_press_start_pos: Vector2 = Vector2.ZERO
var _touch_press_pending: bool = false
var _long_press_triggered: bool = false
var _long_press_timer: SceneTreeTimer = null
const TOUCH_DRAG_THRESHOLD := 50.0
const LONG_PRESS_DURATION := 0.4


func _ready() -> void:
	# Set up card content
	_update_display()

	# Store original values
	original_scale = scale
	original_position = position

	# On touch devices, let events pass through so parent ScrollContainers can scroll.
	# Respect MOUSE_FILTER_IGNORE if already set (e.g. discard pile display card).
	if TouchHelper.is_touch_device() and mouse_filter != Control.MOUSE_FILTER_IGNORE:
		mouse_filter = Control.MOUSE_FILTER_PASS

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
			if event.double_click:
				if is_instance_valid(_last_clicked_card) and _last_clicked_card == self:
					_last_clicked_card = null
					if not is_face_down:
						card_right_clicked.emit(self)
					return
				# Different card or freed — treat as a normal single press
				_last_clicked_card = self
				event.double_click = false
			if event.pressed:
				_last_clicked_card = self
				if TouchHelper.is_touch_device():
					_on_touch_press()
				else:
					_on_mouse_press()
			else:
				if TouchHelper.is_touch_device():
					_on_touch_release()
				else:
					_on_mouse_release()

	elif event is InputEventMouseMotion:
		if TouchHelper.is_touch_device():
			_on_touch_motion()
		elif is_dragging:
			_apply_drag_motion()


## Desktop: left-click press — immediate select or drag start
func _on_mouse_press() -> void:
	if is_selectable:
		if click_on_release:
			_mouse_press_start_pos = get_global_mouse_position()
			return
		card_clicked.emit(self)
		return
	if not drag_enabled or is_face_down:
		return
	is_dragging = true
	drag_offset = get_global_mouse_position() - global_position
	z_index = 100
	drag_started.emit()


## Desktop: left-click release — end drag
func _on_mouse_release() -> void:
	if click_on_release and is_selectable:
		var dist := get_global_mouse_position().distance_to(_mouse_press_start_pos)
		if dist < TOUCH_DRAG_THRESHOLD:
			card_clicked.emit(self)
		return
	if not is_dragging:
		return
	is_dragging = false
	is_snap_previewing = false
	_hover_active = false
	z_index = 0
	drag_ended.emit()


## Touch: press — defer drag/click until motion or release
func _on_touch_press() -> void:
	_touch_press_pending = true
	_long_press_triggered = false
	_touch_press_start_pos = get_global_mouse_position()
	drag_offset = get_global_mouse_position() - global_position
	# Start long-press timer for card preview (skip for draggable cards like hand cards)
	if not is_face_down and not drag_enabled:
		_long_press_timer = get_tree().create_timer(LONG_PRESS_DURATION)
		_long_press_timer.timeout.connect(_on_long_press)


## Touch: long press — show card preview
func _on_long_press() -> void:
	if not _touch_press_pending:
		return
	_touch_press_pending = false
	_long_press_triggered = true
	_long_press_timer = null
	card_right_clicked.emit(self)


## Touch: release — emit tap (card_clicked) or end drag
func _on_touch_release() -> void:
	_cancel_long_press()
	if _long_press_triggered:
		_long_press_triggered = false
		return
	if _touch_press_pending:
		_touch_press_pending = false
		# Only treat as tap if finger didn't drift (e.g. parent ScrollContainer scrolled)
		var dist := get_global_mouse_position().distance_to(_touch_press_start_pos)
		if dist < TOUCH_DRAG_THRESHOLD and is_selectable:
			card_clicked.emit(self)
		return
	# Was dragging — end drag
	if is_dragging:
		is_dragging = false
		is_snap_previewing = false
		_hover_active = false
		z_index = 0
		drag_ended.emit()


## Cancel a pending long-press timer
func _cancel_long_press() -> void:
	if _long_press_timer:
		if _long_press_timer.timeout.is_connected(_on_long_press):
			_long_press_timer.timeout.disconnect(_on_long_press)
		_long_press_timer = null


## Touch: motion — check dead zone, then start drag or update drag position
func _on_touch_motion() -> void:
	if _touch_press_pending:
		var dist := get_global_mouse_position().distance_to(_touch_press_start_pos)
		if dist > TOUCH_DRAG_THRESHOLD:
			_cancel_long_press()
			if drag_enabled and not is_face_down:
				# Exceeded dead zone — start drag
				_touch_press_pending = false
				is_dragging = true
				z_index = 100
				drag_started.emit()
			# If can't drag, keep _touch_press_pending true so release
			# still emits card_clicked (finger slip on selectable card)
	elif is_dragging:
		_apply_drag_motion()


## Shared drag motion logic
func _apply_drag_motion() -> void:
	if is_snap_previewing:
		return
	var new_position = get_global_mouse_position() - drag_offset
	var viewport_size = get_viewport_rect().size
	var card_size = size * scale

	new_position.x = clamp(new_position.x, 0, viewport_size.x - card_size.x)
	new_position.y = clamp(new_position.y, 0, viewport_size.y - card_size.y)

	global_position = new_position


func _on_mouse_entered() -> void:
	if not is_dragging and not is_snap_previewing and not is_locked_in_zone:
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
	if not is_dragging and not is_snap_previewing and not is_locked_in_zone and _hover_active:
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
	# Load effect script if specified (skip in display-only contexts like deck builder)
	if not skip_effect_load:
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


func set_highlight(enabled: bool) -> void:
	var overlay := get_node_or_null("HighlightOverlay") as Panel
	if enabled:
		if not overlay:
			overlay = Panel.new()
			overlay.name = "HighlightOverlay"
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0)
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3
			style.border_color = Color(1.0, 0.85, 0.2, 1.0)
			style.corner_radius_top_left = 6
			style.corner_radius_top_right = 6
			style.corner_radius_bottom_right = 6
			style.corner_radius_bottom_left = 6
			overlay.add_theme_stylebox_override("panel", style)
			add_child(overlay)
		overlay.visible = true
	elif overlay:
		overlay.queue_free()


func _update_display() -> void:
	if not is_node_ready():
		return

	var card_back = get_node_or_null("Background/CardBack")
	var card_image = get_node_or_null("Background/CardImage")

	if is_face_down:
		if card_back:
			card_back.visible = true
			if not _card_back_loaded:
				_card_back_loaded = true
				_default_card_back_texture = load(CARD_BACK_PATH)
				var cb_base := _get_custom_card_back_base()
				var cb_path := _find_custom_file(cb_base, "default")
				if not cb_path.is_empty():
					var image := Image.load_from_file(cb_path)
					if image:
						_custom_card_back_texture = ImageTexture.create_from_image(image)
			var tex: Texture2D = null
			if _custom_card_back_texture and _should_use_custom_back():
				tex = _custom_card_back_texture
			else:
				tex = _default_card_back_texture
			if tex:
				card_back.texture = tex
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
		var is_strategy := _is_strategy_card()
		var set_number := card_number.split("-")[0]
		# Try custom art first
		if use_custom_art and GameSettings.custom_card_art_enabled:
			var custom_cache := _custom_strategy_texture_cache if is_strategy else _custom_texture_cache
			if custom_cache.has(card_number):
				card_image.texture = custom_cache[card_number]
				return
			var custom_dir := _get_custom_art_base().path_join(set_number)
			var custom_path := _find_custom_file(custom_dir, card_number)
			if not custom_path.is_empty():
				var image := Image.load_from_file(custom_path)
				if image:
					if is_strategy:
						image.rotate_90(CLOCKWISE)
					var tex := ImageTexture.create_from_image(image)
					custom_cache[card_number] = tex
					card_image.texture = tex
					return
		# Fall back to standard artwork
		var cache := _strategy_texture_cache if is_strategy else _texture_cache
		if cache.has(card_number):
			card_image.texture = cache[card_number]
			return
		var image_path := ARTWORK_BASE_PATH.path_join(set_number).path_join("%s.png" % card_number)
		var abs_path := ProjectSettings.globalize_path(image_path)
		if FileAccess.file_exists(image_path):
			var image := Image.load_from_file(abs_path)
			if image:
				if is_strategy:
					image.rotate_90(CLOCKWISE)
				var tex := ImageTexture.create_from_image(image)
				cache[card_number] = tex
				card_image.texture = tex


static func clear_texture_cache() -> void:
	_texture_cache.clear()
	_strategy_texture_cache.clear()
	_custom_texture_cache.clear()
	_custom_strategy_texture_cache.clear()
	_default_card_back_texture = null
	_custom_card_back_texture = null
	_card_back_loaded = false


func _should_use_custom_back() -> bool:
	var mode: int = GameSettings.custom_card_back_mode
	if mode == 0:
		return false
	if mode == 2:
		return true
	# Mode 1: myself only
	if owner_player_id == -1:
		return true
	var local_id := NetworkManager.get_local_player_id() if NetworkManager.is_multiplayer() else 0
	return owner_player_id == local_id


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
