extends Control

## Card node with hover scaling, drag functionality, and TCG card image display

const ARTWORK_BASE_PATH := "user://CardContent/Artwork"
const CARD_BACK_PATH := "res://assets/cards/backs/default.jpeg"
const RAGE_MARKER_DEFAULT_PATH := "res://assets/rage/default.png"
const RAGE_MARKER_CUSTOM_DIR := "rage"
const _TriggerMap = preload("res://scripts/effects/trigger_map.gd")

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
static var _texture_cache: Dictionary = {} # card_number -> ImageTexture
static var _strategy_texture_cache: Dictionary = {} # card_number -> ImageTexture (rotated)
static var _custom_texture_cache: Dictionary = {} # card_number -> ImageTexture (custom art)
static var _custom_strategy_texture_cache: Dictionary = {} # card_number -> ImageTexture (custom rotated)
static var _default_card_back_texture: Texture2D = null
static var _custom_card_back_texture: Texture2D = null # null means no custom file found
static var _card_back_loaded: bool = false
static var _rage_marker_default_texture: Texture2D = null
static var _rage_marker_custom_texture: Texture2D = null # null means no custom file found
static var _rage_marker_loaded: bool = false

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
@export var invert_hover: bool = false # When true, hover moves card down instead of up
@export var scale_duration: float = 0.2

# Card data
var card_data: Dictionary = {}
var card_effect: RefCounted = null # CardEffect instance loaded from effect_script
var is_face_down: bool = false
var is_selectable: bool = false
var click_on_release: bool = false # When true, defer card_clicked to mouse release with deadzone
var in_landscape_slot: bool = false
var use_custom_art: bool = true
var skip_effect_load: bool = false # Skip loading effect scripts (e.g. in deck builder)
var owner_player_id: int = -1 # -1 = unset (shows custom art), 0/1 = player ID

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
	# Controller cursor visual (overlay grids are the only place cards get
	# focus — see OverlayGridUtil)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not is_face_down:
				card_right_clicked.emit(self )
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				if is_instance_valid(_last_clicked_card) and _last_clicked_card == self:
					_last_clicked_card = null
					if not is_face_down:
						card_right_clicked.emit(self )
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

	# Controller: overlay-grid cards receive focus (focus_mode set by
	# OverlayGridUtil.wire_grid_focus) and non-mouse events route to the focus
	# owner — confirm activates like a click, inspect like a right-click.
	# Board/hand cards never get focus (GamepadBoardNav cursors them instead).
	elif has_focus():
		if event.is_action_pressed("ui_accept") and is_selectable:
			accept_event()
			card_clicked.emit(self)
		elif event.is_action_pressed("pad_inspect") and not is_face_down:
			accept_event()
			card_right_clicked.emit(self)


## Desktop: left-click press — immediate select or drag start
func _on_mouse_press() -> void:
	if is_selectable:
		if click_on_release:
			_mouse_press_start_pos = get_global_mouse_position()
			return
		card_clicked.emit(self )
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
			card_clicked.emit(self )
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
	card_right_clicked.emit(self )


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
			card_clicked.emit(self )
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
		card_hover_started.emit(self )


func _on_mouse_exited() -> void:
	card_hover_ended.emit(self )
	if not is_dragging and not is_snap_previewing and not is_locked_in_zone and _hover_active:
		z_index = _pre_hover_z_index
		_animate_hover(false)


## Controller cursor visual: mirror the mouse hover raise and add the pulsing
## attention border so the pad position is visible even where hover_scale is
## ~1.0 (overlay galleries). Gated on gamepad mode because pointer clicks also
## grab focus on FOCUS_ALL cards — mouse users must never see the border.
func _on_focus_entered() -> void:
	if not GamepadHelper.is_using_gamepad():
		return
	set_attention_highlight(true)
	_on_mouse_entered()


func _on_focus_exited() -> void:
	set_attention_highlight(false)
	if _hover_active:
		_on_mouse_exited()


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
		tween.tween_property(self , "scale", original_scale * target_hover_scale, scale_duration)
		if not in_slot:
			var lift_dir := 1.0 if invert_hover else -1.0
			tween.tween_property(self , "position", _pre_hover_position + Vector2(0, lift_dir * hover_lift), scale_duration)
	else:
		tween.tween_property(self , "scale", original_scale, scale_duration)
		if not in_slot:
			tween.tween_property(self , "position", _pre_hover_position, scale_duration)
		tween.chain().tween_callback(func(): _hover_active = false)


func _scale_card(target_scale: float) -> void:
	if tween:
		tween.kill()

	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self , "scale", original_scale * target_scale, scale_duration)


## Set card data from a dictionary (TCG format)
func set_card_data_dict(data: Dictionary) -> void:
	card_data = data
	var id: String = data.get("id", "")
	var raw_name: String = data.get("name", "Unknown")
	var raw_desc: String = data.get("description", "")
	if id.is_empty():
		card_name = raw_name
		card_description = raw_desc
	else:
		card_name = _tr_card("CARD_%s_NAME" % id, raw_name)
		card_description = _tr_card("CARD_%s_DESC" % id, raw_desc)
	# Load effect script if specified (skip in display-only contexts like deck builder)
	if not skip_effect_load:
		var script_path: String = data.get("effect_script", "")
		if not script_path.is_empty() and ResourceLoader.exists(script_path):
			var effect_script: GDScript = load(script_path)
			if effect_script:
				card_effect = effect_script.new()
	if is_node_ready():
		_update_display()


static func _tr_card(key: String, fallback: String) -> String:
	var translated: String = TranslationServer.translate(key)
	return fallback if translated == key else translated


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
	tween.tween_property(self , "position", target_pos, duration)
	tween.tween_property(self , "scale", original_scale, duration)


func start_snap_preview(target_pos: Vector2, target_scale: Vector2) -> void:
	is_snap_previewing = true
	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(self , "global_position", target_pos, 0.15)
	tween.tween_property(self , "scale", target_scale, 0.15)


func end_snap_preview() -> void:
	is_snap_previewing = false
	if tween:
		tween.kill()
	scale = original_scale


var _play_cost_modifier: int = 0


## Show a "+N" / "-N" badge near the card's printed cost. Modifier 0 → no badge.
## Card-local position works for all four cases (battle/monster portrait, strategy
## in-hand portrait with pre-rotated texture, and either type in zoom where the
## Card itself is rotated -90°): top-left in card-local always lines up next to
## the visible rank.
func set_play_cost_modifier(modifier: int) -> void:
	_play_cost_modifier = modifier
	var badge := get_node_or_null("PlayCostModifierBadge") as Label
	if modifier == 0:
		# Hide, never free — queue_free is deferred, so a free+recreate on
		# same-frame syncs races with the dying node (badge reuse gotcha).
		if badge:
			badge.visible = false
		return
	if not badge:
		badge = Label.new()
		badge.name = "PlayCostModifierBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(badge)
		if not resized.is_connected(_layout_play_cost_badge):
			resized.connect(_layout_play_cost_badge)
	badge.visible = true
	badge.text = "%+d" % modifier
	if modifier < 0:
		badge.add_theme_color_override("font_color", Color(0.45, 1.0, 0.45))
	else:
		badge.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_layout_play_cost_badge()


func get_play_cost_modifier() -> int:
	return _play_cost_modifier


## Public — call this after changing the card's rotation (e.g. strategy zoom
## flips the card -90°) so the badges re-orient to read upright.
func update_play_cost_badge_layout() -> void:
	_layout_play_cost_badge()
	_layout_stat_badges()


var _power_preview: int = 0


## Show a "+N" power badge over the card's printed CP while it sits in hand —
## a preview of the card's own placement-independent CP modifier (see
## EffectQueries.get_hand_cp_preview). Amount 0 → badge hidden.
## Variable-base cards ("counter power X", e.g. EBP03-067): amount is the
## resolved X itself, rendered unsigned/neutral — it IS the power, not a bonus.
func set_power_preview(amount: int) -> void:
	_power_preview = amount
	var badge := get_node_or_null("PowerPreviewBadge") as Label
	if amount == 0:
		# Hide, never free — queue_free is deferred, so a free+recreate on
		# same-frame syncs races with the dying node (badge reuse gotcha).
		if badge:
			badge.visible = false
		_layout_stat_badges()
		return
	if not badge:
		badge = Label.new()
		badge.name = "PowerPreviewBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(badge)
		if not resized.is_connected(_layout_stat_badges):
			resized.connect(_layout_stat_badges)
	badge.visible = true
	badge.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.3) if _has_variable_base_cp() or amount > 0 else Color(1.0, 0.4, 0.4))
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_layout_stat_badges()


## Whether this card's printed counter power is a variable X resolved by its
## own effect (get_variable_counter_power in the pre-generated trigger map —
## runtime introspection is unreliable in export builds).
func _has_variable_base_cp() -> bool:
	var script_path: String = card_data.get("effect_script", "")
	if script_path.is_empty():
		return false
	return "get_variable_counter_power" in (_TriggerMap.TRIGGERS.get(script_path, []) as Array)


func get_power_preview() -> int:
	return _power_preview


var _threat_preview: int = -1


## Show the resolved variable threat level ("threat level X", e.g. EBP04-031)
## on a preview/zoomed monster card — plain green value in the same band the
## board's ThreatModifierBadge occupies. -1 → badge hidden (fixed printed
## threat is on the art). Unlike the CP preview, 0 stays visible: X = 0 is a
## resolved value the art can't show.
func set_threat_preview(amount: int) -> void:
	_threat_preview = amount
	var badge := get_node_or_null("ThreatPreviewBadge") as Label
	if amount < 0:
		# Hide, never free — queue_free is deferred, so a free+recreate on
		# same-frame syncs races with the dying node (badge reuse gotcha).
		if badge:
			badge.visible = false
		_layout_stat_badges()
		return
	if not badge:
		badge = Label.new()
		badge.name = "ThreatPreviewBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(badge)
		if not resized.is_connected(_layout_stat_badges):
			resized.connect(_layout_stat_badges)
	badge.visible = true
	badge.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_layout_stat_badges()


func get_threat_preview() -> int:
	return _threat_preview


## Zoom-overlay hook: hide every badge drawn over the card art so the printed
## text stays readable; restore from the stored values when re-shown.
func set_stat_badges_visible(shown: bool) -> void:
	if shown:
		set_play_cost_modifier(_play_cost_modifier)
		set_power_preview(_power_preview)
		set_threat_preview(_threat_preview)
		return
	for badge_name in ["PlayCostModifierBadge", "PowerPreviewBadge", "ThreatPreviewBadge"]:
		var badge := get_node_or_null(badge_name) as Label
		if badge:
			badge.visible = false


func _layout_stat_badges() -> void:
	# Power and threat previews share one anchor: the "Counter Power" strip at
	# the card's bottom-right (directly above the printed value). When both are
	# visible they stack upward from it and gain "CP"/"Threat" prefixes so the
	# two values stay distinguishable; alone, each shows the bare number.
	var entries: Array = []
	var power_badge := get_node_or_null("PowerPreviewBadge") as Label
	if power_badge and power_badge.visible:
		entries.append({
			"badge": power_badge,
			"text": ("%d" % _power_preview) if _has_variable_base_cp() else ("%+d" % _power_preview),
			"prefix": "CP",
		})
	var threat_badge := get_node_or_null("ThreatPreviewBadge") as Label
	if threat_badge and threat_badge.visible:
		entries.append({
			"badge": threat_badge,
			"text": "%d" % _threat_preview,
			"prefix": tr("STR_ZOOM_MOD_SEC_THREAT"),
		})
	if entries.is_empty():
		return
	var w: float = size.x if size.x > 0.0 else custom_minimum_size.x
	if w <= 0.0:
		w = 150.0
	var scale_factor: float = w / 150.0
	var h: float = size.y if size.y > 0.0 else custom_minimum_size.y
	if h <= 0.0:
		h = 210.0 * scale_factor
	var bsize := Vector2(64, 20) * scale_factor
	var gap: float = 4.0 * scale_factor
	for i in range(entries.size()):
		var badge: Label = entries[i]["badge"]
		badge.text = ("%s %s" % [entries[i]["prefix"], entries[i]["text"]]) if entries.size() > 1 else str(entries[i]["text"])
		badge.size = bsize
		badge.pivot_offset = bsize / 2.0
		# Counter-rotate for safety (mirrors the other badges).
		badge.position = Vector2(w * 0.865, h * 0.886) - bsize / 2.0 - Vector2(0, (bsize.y + gap) * i)
		badge.rotation = - rotation
		badge.add_theme_font_size_override("font_size", int(round(15.0 * scale_factor)))
		badge.add_theme_constant_override("outline_size", maxi(2, int(round(4.0 * scale_factor))))


func _layout_play_cost_badge() -> void:
	var badge := get_node_or_null("PlayCostModifierBadge") as Label
	if not badge:
		return
	var w: float = size.x if size.x > 0.0 else custom_minimum_size.x
	if w <= 0.0:
		w = 150.0
	var scale_factor: float = w / 150.0
	var bsize := Vector2(34, 22) * scale_factor
	badge.size = bsize
	badge.pivot_offset = bsize / 2.0
	# The rank prints at different visual spots depending on whether the card
	# is rotated for strategy zoom/preview. Pick a card-local center that lands
	# next to the rank in both cases.
	#   - Unrotated (battle/monster portrait, or strategy in hand whose texture
	#     is pre-rotated CW): rank lives at the displayed top-left, badge at
	#     card-local (50, 13) sits just right of it.
	#   - Rotated -90° CCW (strategy zoom/preview): the card-local origin maps
	#     to landscape bottom-left where the rank prints, so we move the badge
	#     down/right in card-local to land just right of the rank in landscape.
	var center: Vector2
	if abs(rotation - (-PI / 2.0)) < 0.05:
		center = Vector2(14, 28) * scale_factor
	else:
		center = Vector2(30, 13) * scale_factor
	badge.position = center - bsize / 2.0
	# Counter the parent card's rotation so the text reads upright. With the
	# pivot at the badge's center, the visual center stays put after both
	# rotations compose to zero.
	badge.rotation = - rotation
	badge.add_theme_font_size_override("font_size", int(round(16.0 * scale_factor)))
	badge.add_theme_constant_override("outline_size", maxi(2, int(round(4.0 * scale_factor))))


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
		# Hide, never queue_free(): a same-frame re-enable would fetch the
		# queued-for-deletion node and the highlight would silently vanish.
		overlay.visible = false


var _attention_tween: Tween = null


func set_attention_highlight(enabled: bool, border_color: Color = Color(0.25, 0.85, 1.0)) -> void:
	## Pulsing border used to point this card out on the board (e.g. while the
	## matching effect-prompt option is hovered) — cyan for the viewer's own
	## effects, purple for the opponent's. Independent of set_highlight's gold
	## border and of modulate-based effect tints, so all three visuals can
	## coexist without stomping each other's reset.
	var overlay := get_node_or_null("AttentionOverlay") as Panel
	if _attention_tween:
		_attention_tween.kill()
		_attention_tween = null
	if enabled:
		if not overlay:
			overlay = Panel.new()
			overlay.name = "AttentionOverlay"
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			overlay.z_index = 3
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0)
			style.border_width_left = 4
			style.border_width_top = 4
			style.border_width_right = 4
			style.border_width_bottom = 4
			style.corner_radius_top_left = 6
			style.corner_radius_top_right = 6
			style.corner_radius_bottom_right = 6
			style.corner_radius_bottom_left = 6
			overlay.add_theme_stylebox_override("panel", style)
			add_child(overlay)
		# Re-color even a cached overlay — the last highlight may have used a
		# different ownership color.
		var box := overlay.get_theme_stylebox("panel") as StyleBoxFlat
		if box:
			box.border_color = border_color
		overlay.visible = true
		overlay.modulate.a = 1.0
		_attention_tween = create_tween().set_loops()
		_attention_tween.set_trans(Tween.TRANS_SINE)
		_attention_tween.tween_property(overlay, "modulate:a", 0.4, 0.4)
		_attention_tween.tween_property(overlay, "modulate:a", 1.0, 0.4)
	elif overlay:
		# Hide, never queue_free(): moving the mouse between two stack rows
		# that target the same card disables and re-enables this highlight in
		# the same frame, so a freed overlay would be picked up again above and
		# the looping tween would target a dead node ("Infinite loop detected"
		# in tween.cpp once every tweener turns invalid).
		overlay.visible = false
		overlay.modulate.a = 1.0


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
		# RAGE-MARKER ships with a built-in default image; it's never
		# downloaded, but the player can still override via the same custom
		# folder pattern as the card back (<custom_base>/rage/default.<ext>).
		if card_number == "RAGE-MARKER":
			_apply_rage_marker_texture(card_image)
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
		# Fall back to standard artwork (try card_art_locale, then en/, then legacy flat path)
		var cache := _strategy_texture_cache if is_strategy else _texture_cache
		var cache_key: String = "%s|%s" % [GameSettings.card_art_locale, card_number]
		if cache.has(cache_key):
			card_image.texture = cache[cache_key]
			return
		var image_path := _find_artwork_path(set_number, card_number)
		if not image_path.is_empty():
			var abs_path := ProjectSettings.globalize_path(image_path)
			var image := Image.load_from_file(abs_path)
			if image:
				if is_strategy:
					image.rotate_90(CLOCKWISE)
				var tex := ImageTexture.create_from_image(image)
				cache[cache_key] = tex
				card_image.texture = tex


static func _apply_rage_marker_texture(card_image: TextureRect) -> void:
	## Load the default RAGE-MARKER image once and cache it. Custom override
	## lives under <custom_base>/rage/default.<ext> (same pattern as the
	## card back) and is used when GameSettings.custom_rage_marker_enabled
	## is true and the file exists.
	if not _rage_marker_loaded:
		_rage_marker_loaded = true
		if ResourceLoader.exists(RAGE_MARKER_DEFAULT_PATH):
			_rage_marker_default_texture = load(RAGE_MARKER_DEFAULT_PATH)
		var custom_dir := GameSettings.get_custom_base_path().path_join(RAGE_MARKER_CUSTOM_DIR)
		var custom_path := _find_custom_file(custom_dir, "default")
		if not custom_path.is_empty():
			var image := Image.load_from_file(custom_path)
			if image:
				_rage_marker_custom_texture = ImageTexture.create_from_image(image)
	var tex: Texture2D = null
	if _rage_marker_custom_texture and GameSettings.custom_rage_marker_enabled:
		tex = _rage_marker_custom_texture
	else:
		tex = _rage_marker_default_texture
	if tex:
		card_image.texture = tex


static func _find_artwork_path(set_number: String, card_number: String) -> String:
	## Resolution order: current locale → en/ fallback → legacy flat path.
	## Returns the first existing `res://`-style path, or "" if none found.
	var candidates: Array[String] = []
	var locale: String = GameSettings.card_art_locale
	var locale_dir: String = ARTWORK_BASE_PATH.path_join(locale).path_join(set_number)
	candidates.append(locale_dir.path_join("%s.png" % card_number))
	if locale != "en":
		var en_dir := ARTWORK_BASE_PATH.path_join("en").path_join(set_number)
		candidates.append(en_dir.path_join("%s.png" % card_number))
	# Legacy flat layout from before per-locale subfolders (pre-migration).
	candidates.append(ARTWORK_BASE_PATH.path_join(set_number).path_join("%s.png" % card_number))
	for p in candidates:
		if FileAccess.file_exists(p):
			return p
	return ""


static func clear_texture_cache() -> void:
	_texture_cache.clear()
	_strategy_texture_cache.clear()
	_custom_texture_cache.clear()
	_custom_strategy_texture_cache.clear()
	_default_card_back_texture = null
	_custom_card_back_texture = null
	_card_back_loaded = false
	_rage_marker_default_texture = null
	_rage_marker_custom_texture = null
	_rage_marker_loaded = false


func _should_use_custom_back() -> bool:
	var mode: int = GameSettings.custom_card_back_mode
	if mode == 0:
		return false
	if mode == 2:
		return true
	# Mode 1: myself only
	if owner_player_id == -1:
		return true
	var local_id := NetworkManager.get_local_player_id() if NetworkManager.is_multiplayer() else (NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0)
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
