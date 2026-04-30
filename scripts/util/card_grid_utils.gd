class_name CardGridUtils

## Pure UI-side helpers for rendering grids of card data Dictionaries.
## Used by overlays that show pools of cards (deck-search, deck-arrange,
## card-select, hand-discard, discard-view, monster-deck-view, zone-stack-view).
##
## Stateless — keep these decoupled from any GameBoard scene so future
## overlay scenes can use them without depending on game_board.gd.


## Group cards by template id for the "stacked" gallery view. Returns an
## ordered Array of `{card_data, count, has_match}` dicts. `matching_ids`
## (instance-id → true) marks groups containing at least one card relevant
## to the current effect (used for highlighting in deck-search / card-select).
static func group_cards(cards: Array, matching_ids: Dictionary = {}) -> Array[Dictionary]:
	var groups: Dictionary = {}
	var order: Array[String] = []
	for card_data in cards:
		var tid := CardUtils.base_id(card_data)
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


## Wire a display-only gallery card with the standard hover scale and the
## right-click / mobile-long-press / desktop-double-click zoom plumbing.
## `on_zoom_request` is invoked as `Callable(card_data: Dictionary,
## play_cost_modifier: int)` whenever the user requests a zoomed view —
## the host scene decides how to render the zoom (overlay, signal, etc.).
##
## Replaces the inline `_set_gallery_hover(card)` + `card.card_right_clicked
## .connect(_on_card_long_press_zoom)` pairing that used to live on game_board.
static func wire_gallery_card(card: Control, on_zoom_request: Callable) -> void:
	card.hover_scale = 1.05
	card.hover_lift = 0.0
	card.gui_input.connect(_on_gallery_card_input.bind(card, on_zoom_request))
	if card.has_signal("card_right_clicked"):
		card.card_right_clicked.connect(_on_long_press.bind(on_zoom_request))


static func _on_gallery_card_input(event: InputEvent, card: Control, on_zoom_request: Callable) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if not ("card_data" in card) or card.card_data.is_empty():
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		on_zoom_request.call(card.card_data, _get_modifier(card))
	elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		# `_last_clicked_card` is set by Card._gui_input AFTER this handler runs,
		# so it holds the card from the prior click — confirms a true double-click
		# on the same card instance.
		var last_card = card._last_clicked_card
		if is_instance_valid(last_card) and last_card == card:
			on_zoom_request.call(card.card_data, _get_modifier(card))


static func _on_long_press(card: Control, on_zoom_request: Callable) -> void:
	if not ("card_data" in card) or card.card_data.is_empty():
		return
	on_zoom_request.call(card.card_data, _get_modifier(card))


static func _get_modifier(card: Control) -> int:
	return card.get_play_cost_modifier() if card.has_method("get_play_cost_modifier") else 0


## Add a yellow "x{count}" badge to the top-right of a card node when count
## is greater than 1. Used in the stacked gallery view to show how many
## copies a group represents.
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
