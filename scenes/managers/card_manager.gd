@tool
extends Node2D
class_name CardManager

## Manages a collection of Card nodes with automatic layout and positioning.
##
## At edit time (@tool), draws a debug rectangle showing the configured
## hand bounds so designers can size and align the layout area visually
## before running the game.

# Signals
signal card_added(card: Control)
signal card_removed(card: Control)
signal cards_reordered()
signal card_selected(card: Control, index: int)
signal hand_card_drag_started(card: Control)
signal hand_card_drag_ended(card: Control)
signal hand_card_right_clicked(card: Control)

# Enums
enum LayoutMode {
	HAND_ARC,      # Cards arranged in an arc (typical for player hand)
	GRID,          # Cards in a grid layout
	STACK,         # Cards stacked on top of each other
	HORIZONTAL,    # Cards in a horizontal line
	VERTICAL       # Cards in a vertical line
}

# Export variables
## How cards lay themselves out within the manager.
##   HAND_ARC   — fanned arc, typical player hand
##   GRID       — uniform grid, see grid_* settings below
##   STACK      — all cards at origin, top one visible
##   HORIZONTAL — single row, alignment-aware
##   VERTICAL   — single column
@export var layout_mode: LayoutMode = LayoutMode.HAND_ARC

## Pixel gap between adjacent cards' centers when they fit
## comfortably inside the bounds. Used by HAND_ARC + HORIZONTAL.
## When the hand has too many cards to fit at this spacing, the
## layout compresses toward `min_card_gap`.
@export var card_spacing: float = 20.0

## Hard cap on card count (0 = unlimited). Calls to `add_card`
## past this limit emit a push_warning and no-op. Set this for a
## fixed-size hand (e.g. 7-card draft) where exceeding the cap
## should be a bug.
@export var max_cards: int = 0

## When true (default), `arrange_cards` is called automatically
## after every add/remove/reorder. Set false if you batch many
## changes and want to call `arrange_cards()` once at the end.
@export var auto_arrange: bool = true

## How long the per-card position/rotation tween takes when
## `arrange_cards(animate=true)` runs. 0 = snap instantly.
@export_range(0.0, 1.0) var arrange_duration: float = 0.3

## Maximum total width for the card cluster. 0 means unlimited.
## Ignored when `left_anchor` + `right_anchor` are both set
## (anchors take precedence and define a more flexible span).
@export var max_width: float = 0.0

# --- Hand bounds + alignment ---
enum HandAlignment { LEFT, CENTER, END }

@export_group("Hand bounds")
## Optional left edge of the hand layout area. Read via .global_position.
## Together with right_anchor, defines the span cards lay out within —
## designer drags two Marker2Ds (or any Node2D) into the inspector slots
## and the cards fill the area between them. When unset, falls back to
## the legacy `max_width` / centered-on-origin behavior.
@export var left_anchor: Node2D:
	set(value):
		left_anchor = value
		_redraw_in_editor()
## Right edge of the hand layout area; pairs with `left_anchor`. Read
## via .global_position.x at runtime — designer can move the markers
## freely (or anchor them to dynamic Controls) and the hand updates.
@export var right_anchor: Node2D:
	set(value):
		right_anchor = value
		_redraw_in_editor()
## How cards align within the bounded area when they don't need to
## overlap (i.e., total card width + gaps fits inside the bounds).
##   LEFT — first card's left edge sits at left_anchor
##   CENTER — cards are centered between anchors (default)
##   END — last card's right edge sits at right_anchor
@export var hand_alignment: HandAlignment = HandAlignment.CENTER:
	set(value):
		hand_alignment = value
		_redraw_in_editor()
## Minimum gap between adjacent cards when they DO need to overlap.
## When hand has lots of cards, gap shrinks toward zero but never
## smaller than this. Negative values let cards overlap themselves.
@export_range(-100.0, 100.0) var min_card_gap: float = -40.0

@export_group("Card appearance")
## Uniform scale applied to cards when added. Use Vector2(0.7, 0.7) for
## an opponent-style smaller hand. Default ONE.
@export var card_scale: Vector2 = Vector2.ONE
## Mark cards face_down=true when added. For opponent hand displays.
@export var default_face_down: bool = false

@export_group("Editor preview")
## Draw a debug rectangle showing the hand bounds at edit time.
@export var draw_bounds_in_editor: bool = true

# Hand arc specific settings
@export_group("Hand Arc Settings")
## Imagined circle radius the cards arc along. Larger = flatter
## fan; smaller = tighter curve. Try values 400–800 for typical
## hand displays.
@export var arc_radius: float = 600.0
## Total angle span (in degrees) of the arc when many cards are
## present. The runtime auto-shrinks this when cards would overflow
## `max_width` / the bounds, so this is the *maximum* spread.
@export var arc_angle: float = 60.0
## How much lower cards at the edge of the arc sit relative to the
## center card. 0 = perfectly straight horizontal arc; positive
## values curve the edges down.
@export var vertical_offset: float = 150.0

# Grid specific settings
@export_group("Grid Settings")
## Cards per row when `layout_mode = GRID`. Subsequent cards wrap
## to a new row.
@export var grid_columns: int = 5
## Vertical pixel distance between row centers in GRID mode.
@export var grid_row_spacing: float = 250.0
## Horizontal pixel distance between column centers in GRID mode.
@export var grid_column_spacing: float = 170.0
@export_group("")

# Internal state
var managed_cards: Array[Control] = []
var card_target_positions: Dictionary = {}  # Maps card to its target position
var card_target_rotations: Dictionary = {}  # Maps card to its target rotation
var dragged_card: Control = null  # Currently dragged card
var dragged_card_original_index: int = -1  # Original index of dragged card
var drop_handled: bool = false  # Set by external listeners to prevent reordering
var _drop_handled_card: Control = null  # Last drag whose drop was handled externally
var selection_mode: bool = false  # When true, clicking selects instead of dragging
var selectable_indices: Array[int] = []  # Which card indices are selectable
var _drag_preview_index: int = -1  # Where the dragged card would be inserted


func _ready() -> void:
	if Engine.is_editor_hint():
		# Edit time: just queue a redraw of the bounds preview.
		queue_redraw()
		return
	# Set up initial cards if any children exist
	for child in get_children():
		if child is Control:
			_register_card(child)

	if auto_arrange:
		arrange_cards()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not dragged_card or not is_instance_valid(dragged_card):
		return
	var new_index := _calculate_insertion_index(dragged_card)
	if new_index != _drag_preview_index:
		_drag_preview_index = new_index
		_arrange_with_drag_gap(new_index)


func _redraw_in_editor() -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if not draw_bounds_in_editor:
		return
	# Resolve which bounds source to draw: anchors first, else max_width.
	# Uses _resolve_bounds() so editor preview matches the runtime layout
	# math (including auto-detected children named LeftAnchor/RightAnchor).
	var local_l: float
	var local_r: float
	var color: Color
	var l_node: Node2D = left_anchor
	var r_node: Node2D = right_anchor
	if l_node == null:
		l_node = get_node_or_null("LeftAnchor") as Node2D
	if r_node == null:
		r_node = get_node_or_null("RightAnchor") as Node2D
	if l_node != null and r_node != null:
		local_l = to_local(l_node.global_position).x
		local_r = to_local(r_node.global_position).x
		color = Color(0.3, 0.7, 1.0, 0.85)  # cyan = anchor-driven
	elif max_width > 0.0:
		local_l = -max_width / 2.0
		local_r = max_width / 2.0
		color = Color(0.7, 0.7, 0.3, 0.6)  # yellow = legacy max_width
	else:
		return
	if local_r <= local_l:
		return
	var width: float = local_r - local_l
	draw_rect(Rect2(local_l, -120.0, width, 240.0), color, false, 2.0)
	# Alignment marker dot — shows where the cluster's reference edge sits.
	var marker_x: float
	match hand_alignment:
		HandAlignment.LEFT: marker_x = local_l
		HandAlignment.END: marker_x = local_r
		_: marker_x = (local_l + local_r) / 2.0
	draw_circle(Vector2(marker_x, 0.0), 6.0, Color(1.0, 0.7, 0.3, 0.95))


## Add a card to the manager
func add_card(card: Control, animate: bool = true) -> void:
	if max_cards > 0 and managed_cards.size() >= max_cards:
		push_warning("CardManager: Maximum cards reached (%d)" % max_cards)
		return

	if card.get_parent() != self:
		if card.get_parent():
			card.get_parent().remove_child(card)
		add_child(card)

	# Apply manager-wide visual policy: scale + face-down.
	if card_scale != Vector2.ONE:
		card.scale = card_scale
		if "original_scale" in card:
			card.original_scale = card_scale
	if default_face_down and card.has_method("set_face_down"):
		card.set_face_down(true)

	_register_card(card)
	card_added.emit(card)

	if auto_arrange:
		arrange_cards(animate)


## Remove a card from the manager
func remove_card(card: Control, animate: bool = true) -> void:
	if card not in managed_cards:
		push_warning("CardManager: Card not found in manager")
		return

	managed_cards.erase(card)
	card_target_positions.erase(card)
	card_target_rotations.erase(card)

	# Disconnect signals if they exist
	if card.has_signal("drag_ended") and card.drag_ended.is_connected(_on_card_drag_ended):
		card.drag_ended.disconnect(_on_card_drag_ended)
	if card.has_signal("drag_started") and card.drag_started.is_connected(_on_card_drag_started):
		card.drag_started.disconnect(_on_card_drag_started)

	card_removed.emit(card)

	if auto_arrange:
		arrange_cards(animate)


## Remove card at specific index
func remove_card_at(index: int, animate: bool = true) -> Control:
	if index < 0 or index >= managed_cards.size():
		push_error("CardManager: Invalid index %d" % index)
		return null

	var card = managed_cards[index]
	remove_card(card, animate)
	return card


## Clear all cards from the manager
func clear_cards(destroy: bool = false) -> void:
	for card in managed_cards.duplicate():
		# Disconnect signals
		if card.has_signal("drag_ended") and card.drag_ended.is_connected(_on_card_drag_ended):
			card.drag_ended.disconnect(_on_card_drag_ended)
		if card.has_signal("drag_started") and card.drag_started.is_connected(_on_card_drag_started):
			card.drag_started.disconnect(_on_card_drag_started)

		if destroy:
			card.queue_free()
		else:
			remove_child(card)

	managed_cards.clear()
	card_target_positions.clear()
	card_target_rotations.clear()


## Get all managed cards
func get_cards() -> Array[Control]:
	return managed_cards.duplicate()


## Get card count
func get_card_count() -> int:
	return managed_cards.size()


## Get card at index
func get_card_at(index: int) -> Control:
	if index < 0 or index >= managed_cards.size():
		return null
	return managed_cards[index]


## Check if manager is full
func is_full() -> bool:
	return max_cards > 0 and managed_cards.size() >= max_cards


## Arrange all cards according to current layout mode
func arrange_cards(animate: bool = true) -> void:
	# Sync scene tree child order to match managed_cards order.
	# Godot uses tree order as a tiebreaker for Control picking,
	# so this must stay in sync with z_index for correct hover targets.
	for i in range(managed_cards.size()):
		if managed_cards[i].get_index() != i:
			move_child(managed_cards[i], i)

	match layout_mode:
		LayoutMode.HAND_ARC:
			_arrange_hand_arc(animate)
		LayoutMode.GRID:
			_arrange_grid(animate)
		LayoutMode.STACK:
			_arrange_stack(animate)
		LayoutMode.HORIZONTAL:
			_arrange_horizontal(animate)
		LayoutMode.VERTICAL:
			_arrange_vertical(animate)

	cards_reordered.emit()


## Private methods

func _register_card(card: Control) -> void:
	if card not in managed_cards:
		managed_cards.append(card)

		# Connect to card drag signals if they exist
		if card.has_signal("drag_ended"):
			card.drag_ended.connect(_on_card_drag_ended.bind(card))
		if card.has_signal("drag_started"):
			card.drag_started.connect(_on_card_drag_started.bind(card))
		if card.has_signal("card_right_clicked"):
			card.card_right_clicked.connect(_on_card_right_clicked)


func _arrange_hand_arc(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return
	# Delegate to the alignment-aware shared layout so anchors + alignment
	# are honored on every arrange call (not just during drag).
	var positions := _compute_slot_positions(count)
	for i in range(count):
		_move_card_to_position(managed_cards[i], positions[i], 0.0, animate, i)


## Compute slot positions for a given count using the current layout mode
func _compute_slot_positions(count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if count == 0:
		return positions
	# Resolve the layout span: anchors win over max_width.
	var bounds := _resolve_bounds()
	var bound_left: float = bounds.x
	var bound_right: float = bounds.y
	var span: float = bound_right - bound_left
	# Card width (assume uniform). Pick a stable reference card —
	# skip the dragged one, since its scale is inflated by hover/drag
	# tweens and would make the layout grow/shrink each frame.
	var card_width: float = _measure_card_width()

	match layout_mode:
		LayoutMode.HAND_ARC:
			var effective_angle = arc_angle
			if span > 0 and count > 1:
				var available: float = span - card_width
				if available > 0:
					var max_half_angle = rad_to_deg(asin(clampf(available / (2.0 * arc_radius), 0.0, 1.0)))
					effective_angle = minf(arc_angle, max_half_angle * 2.0)
			var angle_step = effective_angle / max(1, count - 1) if count > 1 else 0
			var start_angle = -effective_angle / 2.0
			# Native arc is centered on (0, 0); we translate the whole cluster
			# to honor the alignment + bounds.
			var arc_extent: float = _arc_horizontal_extent(count, effective_angle)
			var visible_width: float = arc_extent + card_width
			var shift: float = _cluster_shift(visible_width, bound_left, bound_right)
			for i in range(count):
				var angle = start_angle + (angle_step * i)
				var angle_rad = deg_to_rad(angle)
				var x = shift + sin(angle_rad) * arc_radius
				var half_angle = effective_angle / 2.0 if effective_angle > 0 else 1.0
				var y = -cos(angle_rad) * arc_radius + arc_radius - vertical_offset * abs(angle / half_angle)
				positions.append(Vector2(x, y))
		LayoutMode.HORIZONTAL:
			# When cards fit comfortably, use card_spacing as the center-to-
			# center distance. When they overflow, compress to fit, but never
			# below min_card_gap.
			var effective_spacing: float = card_spacing
			if span > 0 and count > 1:
				var max_spacing: float = (span - card_width) / float(count - 1)
				effective_spacing = minf(card_spacing, max_spacing)
				effective_spacing = maxf(effective_spacing, min_card_gap)
				# Defensive: if min_card_gap pushed us back above the ceiling,
				# re-clamp so the cluster never extends past the bounds.
				if (count - 1) * effective_spacing + card_width > span:
					effective_spacing = max_spacing
			var total_width: float = (count - 1) * effective_spacing
			var visible_width: float = total_width + card_width
			var shift: float = _cluster_shift(visible_width, bound_left, bound_right)
			for i in range(count):
				positions.append(Vector2(shift - total_width / 2.0 + i * effective_spacing, 0))
		_:
			# Fallback: horizontal with card_spacing, alignment-aware.
			var total_width: float = (count - 1) * card_spacing
			var visible_width: float = total_width + card_width
			var shift: float = _cluster_shift(visible_width, bound_left, bound_right)
			for i in range(count):
				positions.append(Vector2(shift - total_width / 2.0 + i * card_spacing, 0))
	return positions


## Resolve [left_x, right_x] in CardManager local space. Anchors take
## priority — both the @export slots AND auto-detected children named
## "LeftAnchor" / "RightAnchor" (any Node2D). Falls back to max_width
## centered on origin, or an unbounded wide span if neither is set.
##
## Uses to_local() so the conversion is correct even when CardManager
## lives under a scaled parent (e.g. an AspectRatioContainer fitting
## a playmat into a non-matching window) — raw global-x subtraction
## would return world-space deltas, which differ from local deltas
## under any non-1.0 ancestor scale.
func _resolve_bounds() -> Vector2:
	var l_node: Node2D = left_anchor
	var r_node: Node2D = right_anchor
	if l_node == null:
		l_node = get_node_or_null("LeftAnchor") as Node2D
	if r_node == null:
		r_node = get_node_or_null("RightAnchor") as Node2D
	if l_node and r_node:
		var l: float = to_local(l_node.global_position).x
		var r: float = to_local(r_node.global_position).x
		if r > l:
			return Vector2(l, r)
		push_warning("[CardManager] Anchors are not in left-to-right order (l=%.1f, r=%.1f). Swap them in the editor." % [l, r])
	if max_width > 0:
		return Vector2(-max_width / 2.0, max_width / 2.0)
	# Unbounded — wide nominal span so layout doesn't try to compress.
	return Vector2(-9999.0, 9999.0)


## Compute where the cluster center should sit given the visible
## cluster width (last card's right edge minus first card's left edge)
## and the bounds. Returns the X offset to translate a "centered on 0"
## cluster to its alignment-correct position.
##
## Unbounded fall-through preserves legacy behavior — cluster stays
## centered on origin (shift = 0) regardless of alignment, since
## without bounds there's no reference edge to align to.
func _cluster_shift(visible_width: float, bound_left: float, bound_right: float) -> float:
	var span: float = bound_right - bound_left
	if span >= 9998.0:
		return 0.0
	match hand_alignment:
		HandAlignment.LEFT:
			return bound_left + visible_width / 2.0
		HandAlignment.END:
			return bound_right - visible_width / 2.0
		_:
			return (bound_left + bound_right) / 2.0


## Stable reference card width for layout math. Skips the dragged
## card (its scale is inflated by drag/hover tweens) and the visually-
## hovered card if we can detect it. Falls back to the configured
## card_scale × default size, then a hard 150px default.
func _measure_card_width() -> float:
	for c in managed_cards:
		if c == dragged_card:
			continue
		if c.size.x <= 0:
			continue
		var s: Vector2 = c.scale
		# If the card exposes original_scale, prefer it — drag/hover
		# tweens leave the live scale inflated.
		if "original_scale" in c:
			var orig = c.get("original_scale")
			if orig is Vector2 and (orig as Vector2).x > 0:
				s = orig
		return c.size.x * s.x
	# Fallback when no card has been added yet (or all are dragged).
	return 150.0 * card_scale.x


## Approximate horizontal extent of the arc layout (last card's center
## minus first card's center). Used by alignment math.
func _arc_horizontal_extent(count: int, effective_angle: float) -> float:
	if count <= 1:
		return 0.0
	var half := effective_angle / 2.0
	return 2.0 * sin(deg_to_rad(half)) * arc_radius


## Arrange non-dragged cards with a gap at gap_index to preview reorder
func _arrange_with_drag_gap(gap_index: int) -> void:
	var total_count := managed_cards.size()
	if total_count <= 1:
		return

	var positions := _compute_slot_positions(total_count)

	# Assign non-dragged cards to slot positions, skipping the gap
	var slot := 0
	for i in range(total_count):
		var card := managed_cards[i]
		if card == dragged_card:
			continue
		if slot == gap_index:
			slot += 1
		_move_card_to_position(card, positions[slot], 0.0, true, slot)
		slot += 1


func _arrange_grid(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return

	var rows = ceili(float(count) / float(grid_columns))
	var start_x = -(grid_columns - 1) * grid_column_spacing / 2.0
	var start_y = -(rows - 1) * grid_row_spacing / 2.0

	for i in range(count):
		var card = managed_cards[i]
		var col = i % grid_columns
		var row = i / grid_columns

		var target_pos = Vector2(
			start_x + col * grid_column_spacing,
			start_y + row * grid_row_spacing
		)

		_move_card_to_position(card, target_pos, 0.0, animate, i)


func _arrange_stack(animate: bool) -> void:
	for i in range(managed_cards.size()):
		var card = managed_cards[i]
		# Slight offset for stacked appearance
		var target_pos = Vector2(i * 2, i * 2)
		_move_card_to_position(card, target_pos, 0.0, animate, i)


func _arrange_horizontal(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return
	# Delegate to the alignment-aware shared layout so anchors + alignment
	# are honored on every arrange call (not just during drag).
	var positions := _compute_slot_positions(count)
	for i in range(count):
		_move_card_to_position(managed_cards[i], positions[i], 0.0, animate, i)


func _arrange_vertical(animate: bool) -> void:
	var count = managed_cards.size()
	if count == 0:
		return

	var total_height = (count - 1) * card_spacing
	var start_y = -total_height / 2.0

	for i in range(count):
		var card = managed_cards[i]
		var target_pos = Vector2(0, start_y + i * card_spacing)
		_move_card_to_position(card, target_pos, 0.0, animate, i)


func restore_drop_handled_card_position() -> void:
	## Move the most-recently drop-handled card back to its hand slot without
	## re-arranging the rest of the hand. Used when an external action that
	## consumed a hand card (e.g. monster play) was cancelled, so the card's
	## data is back in the hand but its visual was left at the drop position.
	if not _drop_handled_card or _drop_handled_card not in managed_cards:
		_drop_handled_card = null
		return
	var idx := managed_cards.find(_drop_handled_card)
	var positions := _compute_slot_positions(managed_cards.size())
	if idx >= 0 and idx < positions.size():
		_move_card_to_position(_drop_handled_card, positions[idx], 0.0, true, idx)
	_drop_handled_card = null


func _move_card_to_position(card: Control, target_pos: Vector2, target_rotation: float, animate: bool, target_z: int = -1) -> void:
	# Store the target position and rotation for this card
	card_target_positions[card] = target_pos
	card_target_rotations[card] = target_rotation

	# Set z_index immediately so input routing matches visual stacking order
	# during the animation (not deferred via tween callback)
	if target_z >= 0:
		card.z_index = target_z

	if animate and arrange_duration > 0:
		# Use the card's built-in return_to_position if available
		if card.has_method("return_to_position"):
			card.return_to_position(target_pos, arrange_duration)
			# Handle rotation separately
			if target_rotation != 0:
				var tween = create_tween()
				tween.tween_property(card, "rotation", target_rotation, arrange_duration)
		else:
			var tween = create_tween()
			tween.set_parallel(true)
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(card, "position", target_pos, arrange_duration)
			if target_rotation != 0:
				tween.tween_property(card, "rotation", target_rotation, arrange_duration)
	else:
		card.position = target_pos
		card.rotation = target_rotation


## Signal handlers

func _on_card_drag_started(card: Control) -> void:
	_drag_preview_index = -1
	# A new drag invalidates any pending drop-handled restore from a previous drag.
	_drop_handled_card = null
	# Store dragging state
	if card in managed_cards:
		dragged_card = card
		dragged_card_original_index = managed_cards.find(card)
		card.z_index = 100
		hand_card_drag_started.emit(card)


func _on_card_drag_ended(card: Control) -> void:
	if card not in managed_cards:
		return

	_drag_preview_index = -1

	# Let external listeners handle the drop first (e.g. dropping on a zone)
	drop_handled = false
	hand_card_drag_ended.emit(card)
	if drop_handled:
		# External handler accepted the drop and is mid-action. Remember the
		# card so restore_drop_handled_card_position() can put it back if the
		# action gets cancelled (e.g. apply_play_cost declined).
		_drop_handled_card = card
		dragged_card = null
		dragged_card_original_index = -1
		return

	# Calculate the new index based on card's current position
	var new_index = _calculate_insertion_index(card)

	# Reorder if the position changed
	if new_index != dragged_card_original_index:
		# Remove from old position
		managed_cards.erase(card)
		# Insert at new position
		managed_cards.insert(new_index, card)

		# Emit reordered signal
		cards_reordered.emit()

	# Clear dragging state
	dragged_card = null
	dragged_card_original_index = -1

	# Rearrange all cards with animation (this will reset positions, rotations, z-index)
	arrange_cards(true)


## Helper methods for reordering

func _calculate_insertion_index(card: Control) -> int:
	"""Calculate where the card should be inserted based on its current position"""
	# Build a list of cards excluding the dragged card
	var other_cards: Array[Control] = []
	for c in managed_cards:
		if c != card:
			other_cards.append(c)

	if other_cards.is_empty():
		return 0

	var card_center = card.global_position + card.size * card.scale / 2.0
	var local_pos = to_local(card_center)

	# Check each position and insert before the first card that's "after" us
	for i in range(other_cards.size()):
		var other_card = other_cards[i]
		if other_card not in card_target_positions:
			continue

		var target_pos = card_target_positions[other_card]

		# For horizontal layouts (hand arc, horizontal line)
		if layout_mode == LayoutMode.HAND_ARC or layout_mode == LayoutMode.HORIZONTAL:
			if local_pos.x < target_pos.x:
				return i  # Insert before this card

		# For vertical layout
		elif layout_mode == LayoutMode.VERTICAL:
			if local_pos.y < target_pos.y:
				return i  # Insert before this card

		# For grid layout, use a combination
		elif layout_mode == LayoutMode.GRID:
			# Compare by row first, then column
			if local_pos.y < target_pos.y - grid_row_spacing / 2:
				return i
			elif local_pos.y < target_pos.y + grid_row_spacing / 2:
				if local_pos.x < target_pos.x:
					return i

	# If we didn't insert before any card, insert at the end
	return other_cards.size()


## Enable selection mode - clicking a card emits card_selected instead of dragging
func enter_selection_mode(valid_indices: Array[int] = []) -> void:
	selection_mode = true
	selectable_indices = valid_indices
	for i in range(managed_cards.size()):
		var card = managed_cards[i]
		var is_valid = valid_indices.is_empty() or i in valid_indices
		if card.has_method("set_face_down"):
			pass  # Don't change face state
		if "is_selectable" in card:
			card.is_selectable = is_valid
		if "drag_enabled" in card:
			card.drag_enabled = false
		if card.has_signal("card_clicked") and not card.card_clicked.is_connected(_on_card_clicked):
			card.card_clicked.connect(_on_card_clicked)


## Disable selection mode - restore normal drag behavior
func exit_selection_mode() -> void:
	selection_mode = false
	selectable_indices = []
	for card in managed_cards:
		if "is_selectable" in card:
			card.is_selectable = false
		if "drag_enabled" in card:
			card.drag_enabled = true
		if card.has_signal("card_clicked") and card.card_clicked.is_connected(_on_card_clicked):
			card.card_clicked.disconnect(_on_card_clicked)


func _on_card_right_clicked(card: Control) -> void:
	hand_card_right_clicked.emit(card)


func _on_card_clicked(card: Control) -> void:
	if not selection_mode:
		return
	var index = managed_cards.find(card)
	if index >= 0:
		card_selected.emit(card, index)
