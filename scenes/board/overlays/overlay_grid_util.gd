class_name OverlayGridUtil
extends RefCounted

## Shared helpers for the card-grid overlays (deck search, card select,
## discard/monster-deck/zone-stack viewers): template grouping, count badges,
## grid teardown, and gallery hover/zoom wiring.


## Extract the template card number from an instance ID.
## Instance IDs: "EBP01-001_1_0" -> "EBP01-001", Monster IDs stay as-is.
static func get_card_template_id(card_data: Dictionary) -> String:
	var id: String = card_data.get("id", "")
	var parts := id.split("_")
	return parts[0] if not parts.is_empty() else id


## Group cards by template ID. Returns Array of {card_data, count, has_match}.
static func group_cards(cards: Array, matching_ids: Dictionary = {}) -> Array[Dictionary]:
	var groups: Dictionary = {} # template_id -> {card_data, count, has_match}
	var order: Array[String] = [] # Preserve first-seen order
	for card_data in cards:
		var tid := get_card_template_id(card_data)
		if groups.has(tid):
			groups[tid]["count"] += 1
			if matching_ids.has(card_data.get("id", "")):
				groups[tid]["has_match"] = true
		else:
			groups[tid] = {
				"card_data": card_data,
				"count": 1,
				"has_match": matching_ids.has(card_data.get("id", "")),
			}
			order.append(tid)

	var result: Array[Dictionary] = []
	for tid in order:
		result.append(groups[tid])
	return result


static func add_count_badge(card: Control, count: int) -> void:
	if count <= 1:
		return
	var badge := Label.new()
	badge.text = "x%d" % count
	badge.add_theme_font_size_override("font_size", 16)
	badge.add_theme_color_override("font_color", Color.YELLOW)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -40
	badge.offset_right = -4
	badge.offset_top = 10
	card.add_child(badge)


## Full-screen prompt overlays must span the viewport; re-assert geometry at
## show time (a degenerate rect was observed in an exported build — the dim
## layer drew nothing and the panel collapsed to the top-left corner).
static func ensure_full_rect(overlay: Control) -> void:
	var parent := overlay.get_parent_control()
	if parent and overlay.size != parent.size:
		push_warning("Overlay %s had degenerate rect %s (parent %s); re-anchoring"
				% [overlay.name, overlay.size, parent.size])
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func clear_grid(grid: GridContainer, click_handler: Callable) -> void:
	for child in grid.get_children():
		if "card_clicked" in child and child.card_clicked.is_connected(click_handler):
			child.card_clicked.disconnect(click_handler)
		child.queue_free()


## ---- Controller navigation -------------------------------------------------
## Overlays are meshed with focus_neighbor paths so the built-in ui_*
## traversal (GamepadInput mirrors pad_nav_* onto ui_*) walks them: the card
## grid is row-major with horizontal wrap inside each row, and the chrome
## rows (toggles above the grid, Skip/Confirm/Close below) join the vertical
## cycle — grid top row ↑ lands on the top chrome, bottom row ↓ on the bottom
## chrome, and the chrome rows link to each other so holding a direction
## tours the whole overlay. Cards handle ui_accept / pad_inspect themselves
## while focused (card.gd); chrome controls must be make_pad_focusable'd by
## their overlay so pointer users never see focus rings. Initial focus is the
## job of the overlay's GamepadHelper.register_modal provider, NOT the mesh.


## Live focusable cards of a grid (skips queued-for-deletion children and
## non-card fillers like the empty-pile label).
static func grid_cards(grid: GridContainer) -> Array[Control]:
	var cards: Array[Control] = []
	for child in grid.get_children():
		if child is Control and not child.is_queued_for_deletion() \
				and child.has_signal("card_clicked"):
			cards.append(child)
	return cards


## Legacy single-grid mesh (self-wrapping, no chrome).
static func wire_grid_focus(grid: GridContainer) -> void:
	wire_overlay_focus(grid, [], [])


## Grid + chrome mesh. Chrome arrays may contain hidden controls — they are
## filtered here, so call sites can pass fixed lists (e.g. an optional Skip).
static func wire_overlay_focus(grid: GridContainer, top_chrome: Array[Control],
		bottom_chrome: Array[Control]) -> void:
	var cards := grid_cards(grid)
	var above := _visible_controls(top_chrome)
	var below := _visible_controls(bottom_chrome)
	_mesh_chrome_row(above)
	_mesh_chrome_row(below)
	_mesh_cards(cards, maxi(grid.columns, 1), above, below)
	_link_chrome_vertical(above, below, cards, maxi(grid.columns, 1))


## Two side-by-side grids sharing the same chrome rows (card select pool /
## selection, deck arrange keep / discard): per-grid meshes plus row-clamped
## cross links so ←/→ cycles through BOTH grids (left edge of the left grid
## wraps to the right edge of the right grid and vice versa).
static func wire_two_grid_focus(left_grid: GridContainer, right_grid: GridContainer,
		top_chrome: Array[Control], bottom_chrome: Array[Control]) -> void:
	var lcards := grid_cards(left_grid)
	var rcards := grid_cards(right_grid)
	var lcols: int = maxi(left_grid.columns, 1)
	var rcols: int = maxi(right_grid.columns, 1)
	var above := _visible_controls(top_chrome)
	var below := _visible_controls(bottom_chrome)
	_mesh_chrome_row(above)
	_mesh_chrome_row(below)
	_mesh_cards(lcards, lcols, above, below)
	_mesh_cards(rcards, rcols, above, below)
	_cross_link_grids(lcards, lcols, rcards, rcols)
	# Chrome anchors vertically onto whichever grid has cards.
	var anchor_cards := lcards if not lcards.is_empty() else rcards
	var anchor_cols := lcols if not lcards.is_empty() else rcols
	_link_chrome_vertical(above, below, anchor_cards, anchor_cols)


## Index of the current focus owner among grid_cards(grid), -1 if elsewhere.
## Capture this BEFORE clear_grid() — it identifies position, not the node.
static func focused_index(grid: GridContainer) -> int:
	if not is_instance_valid(grid) or not grid.is_inside_tree():
		return -1
	var focus_owner := grid.get_viewport().gui_get_focus_owner()
	if focus_owner == null:
		return -1
	return grid_cards(grid).find(focus_owner)


## Deferred, clamped focus grab of the card at `index` (gamepad mode only);
## falls back to `fallback` (e.g. the first chrome control) on an empty grid.
## Deferred + revalidated because callers invoke this right after rebuilding
## the grid, while the previous cards are still queued for deletion.
static func focus_index(grid: GridContainer, index: int, fallback: Control = null) -> void:
	if not GamepadHelper.is_using_gamepad():
		return
	(func() -> void:
		if not is_instance_valid(grid) or not grid.is_inside_tree():
			return
		var cards := grid_cards(grid)
		if not cards.is_empty():
			var card := cards[clampi(index, 0, cards.size() - 1)]
			if card.is_visible_in_tree():
				card.grab_focus()
				return
		if fallback != null and is_instance_valid(fallback) \
				and fallback.is_visible_in_tree():
			fallback.grab_focus()
	).call_deferred()


static func _visible_controls(controls: Array[Control]) -> Array[Control]:
	var out: Array[Control] = []
	for c in controls:
		if c != null and is_instance_valid(c) and c.visible:
			out.append(c)
	return out


## Row-major card mesh: horizontal wrap inside each row; vertically the top
## and bottom rows exit into the chrome rows when present, else wrap onto the
## opposite grid edge (legacy behavior).
static func _mesh_cards(cards: Array[Control], cols: int,
		above: Array[Control], below: Array[Control]) -> void:
	var count := cards.size()
	if count == 0:
		return
	# A lone chrome row serves both vertical exits so the cycle stays closed.
	var up_row := above if not above.is_empty() else below
	var down_row := below if not below.is_empty() else above
	var rows: int = ceili(float(count) / float(cols))
	for i in range(count):
		var card := cards[i]
		card.focus_mode = Control.FOCUS_ALL
		var row: int = i / cols
		var col: int = i % cols
		var row_start: int = row * cols
		var row_end: int = mini(row_start + cols, count) - 1
		var left: int = i - 1 if i > row_start else row_end
		var right: int = i + 1 if i < row_end else row_start
		card.focus_neighbor_left = card.get_path_to(cards[left])
		card.focus_neighbor_right = card.get_path_to(cards[right])
		if row > 0:
			card.focus_neighbor_top = card.get_path_to(cards[i - cols])
		elif not up_row.is_empty():
			card.focus_neighbor_top = card.get_path_to(up_row[mini(col, up_row.size() - 1)])
		else:
			card.focus_neighbor_top = card.get_path_to(cards[mini((rows - 1) * cols + col, count - 1)])
		if i + cols < count:
			card.focus_neighbor_bottom = card.get_path_to(cards[i + cols])
		elif not down_row.is_empty():
			card.focus_neighbor_bottom = card.get_path_to(down_row[mini(col, down_row.size() - 1)])
		else:
			card.focus_neighbor_bottom = card.get_path_to(cards[mini(col, count - 1)])


## ←/→ wrap within a chrome row.
static func _mesh_chrome_row(row: Array[Control]) -> void:
	var n := row.size()
	for i in range(n):
		row[i].focus_neighbor_left = row[i].get_path_to(row[(i - 1 + n) % n])
		row[i].focus_neighbor_right = row[i].get_path_to(row[(i + 1) % n])


## Chrome rows join the grid's vertical cycle: top chrome ↓ enters the grid's
## top row, bottom chrome ↑ enters its bottom row, and the outward directions
## link the two chrome rows to each other (or fall back to the grid when the
## other row is absent). With no cards at all, the chrome rows cycle between
## themselves.
static func _link_chrome_vertical(above: Array[Control], below: Array[Control],
		cards: Array[Control], cols: int) -> void:
	var count := cards.size()
	var last_row_start: int = (ceili(float(count) / float(cols)) - 1) * cols if count > 0 else 0
	for j in range(above.size()):
		var c := above[j]
		if count > 0:
			c.focus_neighbor_bottom = c.get_path_to(cards[mini(j, mini(cols, count) - 1)])
		elif not below.is_empty():
			c.focus_neighbor_bottom = c.get_path_to(below[mini(j, below.size() - 1)])
		if not below.is_empty():
			c.focus_neighbor_top = c.get_path_to(below[mini(j, below.size() - 1)])
		elif count > 0:
			c.focus_neighbor_top = c.get_path_to(cards[mini(last_row_start + j, count - 1)])
	for j in range(below.size()):
		var c := below[j]
		if count > 0:
			c.focus_neighbor_top = c.get_path_to(cards[mini(last_row_start + j, count - 1)])
		elif not above.is_empty():
			c.focus_neighbor_top = c.get_path_to(above[mini(j, above.size() - 1)])
		if not above.is_empty():
			c.focus_neighbor_bottom = c.get_path_to(above[mini(j, above.size() - 1)])
		elif count > 0:
			c.focus_neighbor_bottom = c.get_path_to(cards[mini(j, mini(cols, count) - 1)])


## Row-clamped ←/→ links between two neighboring grids, closing a horizontal
## cycle across both. No-op when either grid is empty (each keeps its own wrap).
static func _cross_link_grids(lcards: Array[Control], lcols: int,
		rcards: Array[Control], rcols: int) -> void:
	if lcards.is_empty() or rcards.is_empty():
		return
	var lrows: int = ceili(float(lcards.size()) / float(lcols))
	var rrows: int = ceili(float(rcards.size()) / float(rcols))
	for row in range(lrows):
		var row_start: int = row * lcols
		var row_end: int = mini(row_start + lcols, lcards.size()) - 1
		var target_row: int = mini(row, rrows - 1)
		var r_start: int = mini(target_row * rcols, rcards.size() - 1)
		var r_end: int = mini(target_row * rcols + rcols, rcards.size()) - 1
		var lfirst := lcards[row_start]
		var llast := lcards[row_end]
		llast.focus_neighbor_right = llast.get_path_to(rcards[r_start])
		lfirst.focus_neighbor_left = lfirst.get_path_to(rcards[r_end])
	for row in range(rrows):
		var row_start: int = row * rcols
		var row_end: int = mini(row_start + rcols, rcards.size()) - 1
		var target_row: int = mini(row, lrows - 1)
		var l_start: int = mini(target_row * lcols, lcards.size() - 1)
		var l_end: int = mini(target_row * lcols + lcols, lcards.size()) - 1
		var rfirst := rcards[row_start]
		var rlast := rcards[row_end]
		rlast.focus_neighbor_right = rlast.get_path_to(lcards[l_start])
		rfirst.focus_neighbor_left = rfirst.get_path_to(lcards[l_end])


const _CardScript := preload("res://scenes/cards/card.gd")
## Same top-crop offset the deck list rows use (DeckRow.THUMB_CROP_Y_RATIO).
const THUMB_CROP_Y_RATIO := 0.08

static var _thumb_cache: Dictionary = {} # base card id -> Texture2D (or null)


## Square thumbnail of a card's artwork for choice buttons, matching the
## deck-list row crop: battle/monster cards show the TOP of the card
## (offset by THUMB_CROP_Y_RATIO). Strategy cards appear sideways in play
## (card.gd rotates their landscape scans CLOCKWISE onto the portrait card
## node), so showing the scan as-is equals rotating the in-game card 90°
## counter-clockwise back to readable — the square is taken from the
## CENTER of that upright image.
## `card_id` must be a base id ("EBP04-067", no per-copy suffix).
static func get_choice_thumb(card_id: String) -> Texture2D:
	if card_id.is_empty():
		return null
	if _thumb_cache.has(card_id):
		return _thumb_cache[card_id]
	var set_number := card_id.split("-")[0]
	var path: String = _CardScript._find_artwork_path(set_number, card_id)
	if path.is_empty():
		_thumb_cache[card_id] = null
		return null
	var img := Image.new()
	if img.load(path) != OK:
		_thumb_cache[card_id] = null
		return null

	var data: Dictionary = CardData.get_card_by_id(card_id)
	var is_strategy: bool = data.get("card_type") == CardEnums.CardType.STRATEGY

	var base := ImageTexture.create_from_image(img)
	var w := img.get_width()
	var h := img.get_height()
	var side := mini(w, h)
	var region: Rect2
	if is_strategy:
		# Center square of the upright strategy card
		region = Rect2((w - side) / 2.0, (h - side) / 2.0, side, side)
	else:
		# Top portion, same offset as the deck list thumbnails
		var y_offset := int(h * THUMB_CROP_Y_RATIO)
		if y_offset + side > h:
			y_offset = maxi(0, h - side)
		region = Rect2(0, y_offset, side, side)
	var atlas := AtlasTexture.new()
	atlas.atlas = base
	atlas.region = region
	_thumb_cache[card_id] = atlas
	return atlas


## Gallery hover + zoom wiring: subtle hover scale, right-click or
## double-click calls zoom_request(card_data, 0).
static func set_gallery_hover(card: Control, zoom_request: Callable) -> void:
	card.hover_scale = 1.05
	card.hover_lift = 0.0
	card.gui_input.connect(_on_gallery_card_input.bind(card, zoom_request))


static func _on_gallery_card_input(event: InputEvent, card: Control, zoom_request: Callable) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if "card_data" in card and not card.card_data.is_empty() and zoom_request.is_valid():
			zoom_request.call(card.card_data, 0)
	elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		# Only treat as double-click if the same card instance was clicked both
		# times. _last_clicked_card is a static var set in card._gui_input (which
		# runs AFTER this signal handler), so it holds the PREVIOUS click's card.
		var last_card = card._last_clicked_card
		if is_instance_valid(last_card) and last_card == card:
			if "card_data" in card and not card.card_data.is_empty() and zoom_request.is_valid():
				zoom_request.call(card.card_data, 0)
