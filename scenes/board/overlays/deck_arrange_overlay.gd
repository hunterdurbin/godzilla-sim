extends ColorRect

## Deck-arrange effect overlay: drag-and-drop cards between two ordered
## panels (KeepOnDeck / SendToDiscard). Cards reorder within and across
## panels by dropping at the appropriate insert point.
##
## Public API:
##   open(cards, prompt, on_zoom_request, on_resolve, on_view_board)
##   handle_drag_motion()                     -- caller (game_board) forwards
##                                                each frame's mouse motion
##                                                while a card is being dragged
##                                                (mouse-grab is broken by the
##                                                reparenting trick we use)
##   handle_drag_release()                    -- caller forwards mouse-up
##   has_dragging_card() -> bool              -- caller gates input handling
##   close()
##   signal closed
##
## `on_resolve(keep: Array, discard: Array)` is invoked when the user
## confirms. `on_view_board()` lets the host hide the overlay so the
## player can peek at the board.

signal closed

@export var prompt_key: String = "deck_arrange"
@export var auto_register: bool = true

const _CARD_SCENE := preload("res://scenes/cards/Card.tscn")
const _CARD_SIZE := Vector2(100, 140)

@onready var _prompt: Label = $DeckArrangePanel/VBox/PromptLabel
@onready var _keep_panel: PanelContainer = $DeckArrangePanel/VBox/ArrangeContainer/KeepPanel
@onready var _keep_grid: GridContainer = $DeckArrangePanel/VBox/ArrangeContainer/KeepPanel/KeepVBox/KeepCards
@onready var _discard_panel: PanelContainer = $DeckArrangePanel/VBox/ArrangeContainer/DiscardPanel
@onready var _discard_grid: GridContainer = $DeckArrangePanel/VBox/ArrangeContainer/DiscardPanel/DiscardVBox/DiscardCards
@onready var _view_board_btn: Button = $DeckArrangePanel/VBox/ButtonRow/ViewBoardButton
@onready var _confirm_btn: Button = $DeckArrangePanel/VBox/ButtonRow/ConfirmButton

var _keep: Array = []
var _discard: Array = []

var _on_zoom_request: Callable = Callable()
var _on_resolve: Callable = Callable()
var _on_view_board: Callable = Callable()

var _dragging_card: Control = null
var _drag_source: String = ""
var _drag_index: int = -1
var _drop_indicator: ColorRect = null


func _ready() -> void:
	visible = false
	z_index = 100
	_view_board_btn.pressed.connect(_on_view_board_pressed)
	_confirm_btn.pressed.connect(_on_confirm)
	if GameSettings.use_mobile_layout:
		_apply_mobile_sizing()
	if auto_register:
		var router := BoardModule.find_router(self)
		if router:
			router.register_handler(prompt_key, _on_router_show)


func _on_router_show(cards: Array, prompt: String, resolve_cb: Callable) -> void:
	var router := BoardModule.find_router(self)
	open(cards, prompt, router.card_zoom_request, resolve_cb, _ask_host_to_view_board)


func _ask_host_to_view_board() -> void:
	var router := BoardModule.find_router(self)
	if router and router.on_view_board_request.is_valid():
		router.on_view_board_request.call(self)


func _apply_mobile_sizing() -> void:
	for btn in [_view_board_btn, _confirm_btn]:
		btn.custom_minimum_size.y = 55
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS


func has_dragging_card() -> bool:
	return _dragging_card != null


func handle_drag_motion() -> void:
	if not _dragging_card:
		return
	_dragging_card.global_position = get_global_mouse_position() - _dragging_card.drag_offset
	_update_drop_indicator()


func handle_drag_release() -> void:
	if not _dragging_card:
		return
	_dragging_card.is_dragging = false
	_dragging_card.z_index = 0
	_on_drag_ended(_dragging_card)


func open(
	cards: Array,
	prompt: String,
	on_zoom_request: Callable,
	on_resolve: Callable,
	on_view_board: Callable,
) -> void:
	_keep = cards.duplicate()
	_discard = []
	_on_zoom_request = on_zoom_request
	_on_resolve = on_resolve
	_on_view_board = on_view_board
	_prompt.text = prompt
	visible = true
	_refresh()


func reshow() -> void:
	visible = true


func close() -> void:
	visible = false
	_clear_grids()
	_keep.clear()
	_discard.clear()
	closed.emit()


func _on_view_board_pressed() -> void:
	visible = false
	if _on_view_board.is_valid():
		_on_view_board.call()


func _on_confirm() -> void:
	visible = false
	var keep := _keep.duplicate()
	var discard := _discard.duplicate()
	_clear_grids()
	_keep.clear()
	_discard.clear()
	if _on_resolve.is_valid():
		_on_resolve.call(keep, discard)


func _clear_grids() -> void:
	for child in _keep_grid.get_children():
		child.queue_free()
	for child in _discard_grid.get_children():
		child.queue_free()


func _refresh() -> void:
	# Free existing card instances
	_clear_grids()

	for i in range(_keep.size()):
		var card := _create_card(_keep[i])
		card.drag_started.connect(_on_drag_started.bind(card, "keep", i))
		card.drag_ended.connect(_on_drag_ended.bind(card))
		_keep_grid.add_child(card)
		_add_position_badge(card, i + 1)

	for i in range(_discard.size()):
		var card := _create_card(_discard[i])
		card.drag_started.connect(_on_drag_started.bind(card, "discard", i))
		card.drag_ended.connect(_on_drag_ended.bind(card))
		_discard_grid.add_child(card)


func _create_card(card_data: Dictionary) -> Control:
	var card: Control = _CARD_SCENE.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	card.custom_minimum_size = _CARD_SIZE
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.drag_enabled = true
	card.is_selectable = false
	if _on_zoom_request.is_valid():
		CardGridUtils.wire_gallery_card(card, _on_zoom_request)
	return card


func _on_drag_started(card: Control, source: String, index: int) -> void:
	_dragging_card = card
	_drag_source = source
	_drag_index = index
	# Hover tween keeps running after reparent and overrides position; kill it.
	if card.tween and card.tween.is_valid():
		card.tween.kill()
	card.scale = Vector2.ONE
	# Drop-indicator is positioned absolutely over the overlay (not in a grid).
	_drop_indicator = ColorRect.new()
	_drop_indicator.custom_minimum_size = Vector2(3, 140)
	_drop_indicator.size = Vector2(3, 140)
	_drop_indicator.color = Color(0.4, 0.7, 1.0, 0.9)
	_drop_indicator.visible = false
	add_child(_drop_indicator)
	# Capture position before reparenting out of the grid
	var gpos := card.global_position
	card.get_parent().remove_child(card)
	add_child(card)
	# Zero anchors left over from grid layout, restore position
	card.anchor_left = 0.0
	card.anchor_top = 0.0
	card.anchor_right = 0.0
	card.anchor_bottom = 0.0
	card.size = _CARD_SIZE
	card.global_position = gpos


func _on_drag_ended(card: Control) -> void:
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
	var container: GridContainer = _keep_grid if target == "keep" else _discard_grid
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
		container = _keep_grid
		target_name = "keep"
	elif discard_rect.has_point(card_center):
		container = _discard_grid
		target_name = "discard"

	if container == null or container.get_child_count() == 0:
		_drop_indicator.visible = false
		return

	var insert_idx := _get_insert_index(card_center, target_name)
	insert_idx = clampi(insert_idx, 0, container.get_child_count())

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
