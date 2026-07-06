class_name DeckArrangeOverlayUI
extends ColorRect

## Deck-arrange prompt overlay: drag cards between Keep (ordered, with
## position badges) and Discard areas, then confirm. Registered with
## EffectUIRouter as the "deck_arrange" handler.
##
## Drag tracking runs through handle_drag_input(), called from the board's
## _input — reparenting the dragged card breaks gui_input mouse grab, so the
## board-level input hook is load-bearing.

const CARD_SCENE: PackedScene = preload("res://scenes/cards/Card.tscn")

@onready var _prompt: Label = $DeckArrangePanel/VBox/PromptLabel
@onready var _keep_panel: PanelContainer = $DeckArrangePanel/VBox/ArrangeContainer/KeepPanel
@onready var _keep_cards: GridContainer = $DeckArrangePanel/VBox/ArrangeContainer/KeepPanel/KeepVBox/KeepCards
@onready var _discard_panel: PanelContainer = $DeckArrangePanel/VBox/ArrangeContainer/DiscardPanel
@onready var _discard_cards: GridContainer = $DeckArrangePanel/VBox/ArrangeContainer/DiscardPanel/DiscardVBox/DiscardCards
@onready var _view_board: Button = $DeckArrangePanel/VBox/ButtonRow/ViewBoardButton
@onready var _confirm: Button = $DeckArrangePanel/VBox/ButtonRow/ConfirmButton

var _router: EffectUIRouter

var _keep: Array[Dictionary] = []
var _discard: Array[Dictionary] = []
var _dragging_card: Control = null
var _drag_source: String = "" # "keep" or "discard"
var _drag_index: int = -1
var _drop_indicator: ColorRect = null
var _resolve_cb: Callable = Callable()


func _ready() -> void:
	visible = false
	z_index = 100
	_router = get_node_or_null("../GameSession/EffectUIRouter")
	_view_board.pressed.connect(_on_view_board)
	_confirm.pressed.connect(_on_confirm)
	# Controller: take a focus context while visible (suspends the board
	# cursor, restores it on close/minimize) and keep the chrome free of
	# pointer-mode focus rings.
	GamepadHelper.register_modal(self, _pad_focus_provider)
	GamepadHelper.make_pad_focusable(_view_board)
	GamepadHelper.make_pad_focusable(_confirm)
	var hints := OverlayHintRow.new()
	hints.set_hints([
		{"action": &"pad_confirm", "text": tr("STR_GB_HINT_MOVE")},
		{"action": &"pad_focus_log", "action2": &"pad_focus_tracker",
				"text": tr("STR_GB_HINT_REORDER")},
		{"action": &"pad_inspect", "text": tr("STR_GB_HINT_INSPECT")},
	])
	$DeckArrangePanel/VBox.add_child(hints)


## Initial pad focus: first Keep card, else first Discard card, else chrome.
func _pad_focus_provider() -> Control:
	for grid in [_keep_cards, _discard_cards]:
		var grid_cards := OverlayGridUtil.grid_cards(grid)
		if not grid_cards.is_empty():
			return grid_cards[0]
	return GamepadHelper.find_first_focusable(self)


## Controller model (mouse drag stays untouched): A moves the focused card to
## the end of the other pile; LB/RB shift a focused Keep card one slot
## left/right. The bumper actions (pad_focus_log / pad_focus_tracker) are free
## here — GamepadBoardNav suspends while any overlay is open — and follow the
## user's rebinds automatically. Listen to ui_accept only: GamepadInput
## mirrors pad_confirm onto it, so handling both would double-fire.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not GamepadHelper.is_top_context(self):
		return
	var loc := _focused_card_loc()
	if loc.is_empty():
		return
	var source: String = loc["source"]
	var index: int = loc["index"]
	if event.is_action_pressed("ui_accept"):
		_pad_toggle(source, index)
	elif event.is_action_pressed("pad_focus_log") and source == "keep":
		_pad_shift(index, -1)
	elif event.is_action_pressed("pad_focus_tracker") and source == "keep":
		_pad_shift(index, +1)
	else:
		return
	accept_event()


## {source: "keep"/"discard", index: int} of the focused card, {} if focus is
## elsewhere (chrome, nothing).
func _focused_card_loc() -> Dictionary:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null:
		return {}
	var idx := OverlayGridUtil.grid_cards(_keep_cards).find(focus)
	if idx >= 0:
		return {"source": "keep", "index": idx}
	idx = OverlayGridUtil.grid_cards(_discard_cards).find(focus)
	if idx >= 0:
		return {"source": "discard", "index": idx}
	return {}


func _pad_toggle(source: String, index: int) -> void:
	if not pad_toggle(_keep, _discard, source, index):
		return
	_refresh()
	# Stay in place — same pile, same clamped index — so repeated A drains a
	# pile; when it empties, follow the card into the other pile.
	var grid := _keep_cards if source == "keep" else _discard_cards
	var other := _discard_cards if source == "keep" else _keep_cards
	var fallback: Control = _confirm
	var other_cards := OverlayGridUtil.grid_cards(other)
	if not other_cards.is_empty():
		fallback = other_cards.back()
	OverlayGridUtil.focus_index(grid, index, fallback)


func _pad_shift(index: int, delta: int) -> void:
	var new_idx := pad_shift(_keep, index, delta)
	if new_idx < 0:
		return
	_refresh()
	# Focus follows the card to its new slot.
	OverlayGridUtil.focus_index(_keep_cards, new_idx, _confirm)


## Pure pile math for the pad model (unit-tested). Moves the source pile's
## card at `index` to the end of the other pile; false when out of range.
static func pad_toggle(keep: Array[Dictionary], discard: Array[Dictionary],
		source: String, index: int) -> bool:
	var from := keep if source == "keep" else discard
	var to := discard if source == "keep" else keep
	if index < 0 or index >= from.size():
		return false
	to.append(from[index])
	from.remove_at(index)
	return true


## Shifts cards[index] by delta; returns the new index, or -1 for a no-op
## (edge of the pile / bad index).
static func pad_shift(cards: Array[Dictionary], index: int, delta: int) -> int:
	var target := index + delta
	if index < 0 or index >= cards.size() or target < 0 or target >= cards.size():
		return -1
	var card: Dictionary = cards[index]
	cards.remove_at(index)
	cards.insert(target, card)
	return target


## Router handler entry point — `prompt` arrives already translated.
func show_prompt(cards: Array, prompt: String, resolve_cb: Callable) -> void:
	OverlayGridUtil.ensure_full_rect(self)
	_keep.assign(cards.duplicate())
	_discard = []
	_resolve_cb = resolve_cb
	_prompt.text = prompt
	visible = true
	_refresh()


## Board _input hook: returns true when the event was consumed by an active
## card drag (reparenting breaks gui_input mouse grab, so drag tracking must
## happen at the _input level).
func handle_drag_input(event: InputEvent) -> bool:
	if not _dragging_card:
		return false
	if event is InputEventMouseMotion:
		_dragging_card.global_position = get_global_mouse_position() - _dragging_card.drag_offset
		_update_drop_indicator()
		return true
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging_card.is_dragging = false
		_dragging_card.z_index = 0
		_on_card_drag_ended(_dragging_card)
		return true
	return false


func _refresh() -> void:
	for grid in [_keep_cards, _discard_cards]:
		for child in grid.get_children():
			if child.drag_started.is_connected(_on_card_drag_started):
				child.drag_started.disconnect(_on_card_drag_started)
			if child.drag_ended.is_connected(_on_card_drag_ended):
				child.drag_ended.disconnect(_on_card_drag_ended)
			child.queue_free()

	# Populate keep area (ordered, with position badges)
	for i in range(_keep.size()):
		var card: Control = _create_card(_keep[i])
		card.drag_started.connect(_on_card_drag_started.bind(card, "keep", i))
		card.drag_ended.connect(_on_card_drag_ended.bind(card))
		_keep_cards.add_child(card)
		_add_position_badge(card, i + 1)

	# Populate discard area
	for i in range(_discard.size()):
		var card: Control = _create_card(_discard[i])
		card.drag_started.connect(_on_card_drag_started.bind(card, "discard", i))
		card.drag_ended.connect(_on_card_drag_ended.bind(card))
		_discard_cards.add_child(card)

	OverlayGridUtil.wire_two_grid_focus(_keep_cards, _discard_cards, [], [_view_board, _confirm])


func _create_card(card_data: Dictionary) -> Control:
	var card: Control = CARD_SCENE.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	card.custom_minimum_size = Vector2(100, 140)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.drag_enabled = true
	card.is_selectable = false
	OverlayGridUtil.set_gallery_hover(card, _router.card_zoom_request if _router else Callable())
	card.card_right_clicked.connect(_on_card_zoom)
	return card


func _on_card_zoom(card: Control) -> void:
	if _router and _router.card_zoom_request.is_valid() and "card_data" in card:
		_router.card_zoom_request.call(card.card_data, 0)


func _on_card_drag_started(card: Control, source: String, index: int) -> void:
	_dragging_card = card
	_drag_source = source
	_drag_index = index
	# Kill hover tween — it keeps running after reparent and overrides position
	if card.tween and card.tween.is_valid():
		card.tween.kill()
	card.scale = Vector2.ONE
	# Create drop indicator (positioned absolutely over the overlay, not inside the grid)
	_drop_indicator = ColorRect.new()
	_drop_indicator.custom_minimum_size = Vector2(3, 140)
	_drop_indicator.size = Vector2(3, 140)
	_drop_indicator.color = Color(0.4, 0.7, 1.0, 0.9)
	_drop_indicator.visible = false
	add_child(_drop_indicator)
	# Capture position before reparenting out of grid
	var gpos := card.global_position
	card.get_parent().remove_child(card)
	add_child(card)
	# Zero anchors left over from grid layout and restore position
	card.anchor_left = 0.0
	card.anchor_top = 0.0
	card.anchor_right = 0.0
	card.anchor_bottom = 0.0
	card.size = Vector2(100, 140)
	card.global_position = gpos


func _on_card_drag_ended(card: Control) -> void:
	var card_center := card.global_position + card.size * card.scale / 2.0
	var keep_rect := _keep_panel.get_global_rect()
	var discard_rect := _discard_panel.get_global_rect()

	if keep_rect.has_point(card_center):
		var card_data: Dictionary
		if _drag_source == "keep":
			card_data = _keep[_drag_index]
			_keep.remove_at(_drag_index)
		else:
			card_data = _discard[_drag_index]
			_discard.remove_at(_drag_index)
		var insert_idx := _get_insert_index(card_center, "keep")
		insert_idx = clampi(insert_idx, 0, _keep.size())
		_keep.insert(insert_idx, card_data)
	elif discard_rect.has_point(card_center):
		var card_data: Dictionary
		if _drag_source == "keep":
			card_data = _keep[_drag_index]
			_keep.remove_at(_drag_index)
		else:
			card_data = _discard[_drag_index]
			_discard.remove_at(_drag_index)
		var insert_idx := _get_insert_index(card_center, "discard")
		insert_idx = clampi(insert_idx, 0, _discard.size())
		_discard.insert(insert_idx, card_data)
	# else: dropped outside both panels — no change

	if _drop_indicator and is_instance_valid(_drop_indicator):
		_drop_indicator.queue_free()
		_drop_indicator = null
	card.queue_free()
	_dragging_card = null
	_refresh()


func _get_insert_index(drop_pos: Vector2, target: String) -> int:
	var container: GridContainer = _keep_cards if target == "keep" else _discard_cards
	var best_idx := container.get_child_count()
	var best_dist := INF
	for i in range(container.get_child_count()):
		var child: Control = container.get_child(i) as Control
		var child_center := child.global_position + child.size * child.scale / 2.0
		var dist: float = drop_pos.distance_squared_to(child_center)
		if dist < best_dist:
			best_dist = dist
			if drop_pos.x < child_center.x:
				best_idx = i
			else:
				best_idx = i + 1
	return best_idx


func _update_drop_indicator() -> void:
	if not _drop_indicator or not is_instance_valid(_drop_indicator):
		return
	var card_center := _dragging_card.global_position + _dragging_card.size * _dragging_card.scale / 2.0
	var keep_rect := _keep_panel.get_global_rect()
	var discard_rect := _discard_panel.get_global_rect()

	var container: GridContainer = null
	var target_name := ""
	if keep_rect.has_point(card_center):
		container = _keep_cards
		target_name = "keep"
	elif discard_rect.has_point(card_center):
		container = _discard_cards
		target_name = "discard"

	if container == null or container.get_child_count() == 0:
		_drop_indicator.visible = false
		return

	var insert_idx := _get_insert_index(card_center, target_name)
	insert_idx = clampi(insert_idx, 0, container.get_child_count())

	# Get the reference card for positioning (the card at or just before the insert point)
	var ref_child: Control
	var line_x: float
	if insert_idx < container.get_child_count():
		ref_child = container.get_child(insert_idx) as Control
		line_x = ref_child.global_position.x - 2.0
	else:
		ref_child = container.get_child(container.get_child_count() - 1) as Control
		line_x = ref_child.global_position.x + ref_child.size.x * ref_child.scale.x + 2.0

	_drop_indicator.global_position = Vector2(line_x, ref_child.global_position.y)
	_drop_indicator.size.y = ref_child.size.y * ref_child.scale.y
	_drop_indicator.visible = true


func _add_position_badge(card: Control, pos: int) -> void:
	var badge := Label.new()
	badge.name = "PositionBadge"
	badge.text = str(pos)
	badge.add_theme_font_size_override("font_size", 16)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 4)
	badge.position = Vector2(8, 8)
	card.add_child(badge)


func _on_view_board() -> void:
	visible = false
	if _router and _router.on_view_board_request.is_valid():
		_router.on_view_board_request.call(self)


## Label data for the minimize chip shown while this overlay is hidden.
func get_minimize_info() -> Dictionary:
	return {"title": _prompt.text, "count": _keep.size() + _discard.size()}


func _on_confirm() -> void:
	visible = false
	var keep := _keep.duplicate()
	var discard := _discard.duplicate()
	_keep.clear()
	_discard.clear()
	for child in _keep_cards.get_children():
		child.queue_free()
	for child in _discard_cards.get_children():
		child.queue_free()
	var cb := _resolve_cb
	_resolve_cb = Callable()
	if cb.is_valid():
		cb.call(keep, discard)
