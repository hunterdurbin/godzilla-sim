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


static func clear_grid(grid: GridContainer, click_handler: Callable) -> void:
	for child in grid.get_children():
		if "card_clicked" in child and child.card_clicked.is_connected(click_handler):
			child.card_clicked.disconnect(click_handler)
		child.queue_free()


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
