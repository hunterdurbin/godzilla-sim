extends ColorRect

## Multi-card selection overlay used by effects that ask the player to pick
## N to M cards from a pool. Two-pane UI: pool on the left (clickable matches),
## selection on the right (click to remove). Confirms when count is in range.
##
## Public API:
##   open(matching, all_cards, prompt, min_count, max_count, stacked,
##        on_zoom_request, on_resolve, on_view_board, pool_filter)
##   close()
##   signal stacked_toggled(stacked)
##   signal closed
##
## `on_resolve(selected: Array)` — empty array means skip.
## `pool_filter(card_data, current_selection) -> bool` is optional; when
## present it disables pool cards that fail the filter (used by effects
## with side-constrained selections like "no two of the same color").

signal stacked_toggled(stacked: bool)
signal closed

const _CARD_SCENE := preload("res://scenes/cards/Card.tscn")
const _CARD_SIZE := Vector2(120, 168)

@onready var _prompt: Label = $CardSelectPanel/VBox/PromptLabel
@onready var _show_all_toggle: CheckButton = $CardSelectPanel/VBox/ToggleRow/ShowAllToggle
@onready var _stacked_toggle: CheckButton = $CardSelectPanel/VBox/ToggleRow/StackedToggle
@onready var _view_board_btn: Button = $CardSelectPanel/VBox/ToggleRow/ViewBoardButton
@onready var _pool_grid: GridContainer = $CardSelectPanel/VBox/ContentContainer/PoolPanel/PoolVBox/ScrollContainer/PoolGrid
@onready var _selection_grid: GridContainer = $CardSelectPanel/VBox/ContentContainer/SelectionPanel/SelectionVBox/ScrollContainer/SelectionGrid
@onready var _selection_label: Label = $CardSelectPanel/VBox/ContentContainer/SelectionPanel/SelectionVBox/SelectionLabel
@onready var _skip_btn: Button = $CardSelectPanel/VBox/ButtonRow/SkipButton
@onready var _confirm_btn: Button = $CardSelectPanel/VBox/ButtonRow/ConfirmButton

var _matching: Array = []
var _all_cards: Array = []
var _matching_ids: Dictionary = {}
var _selected: Array = []
var _min_count: int = 0
var _max_count: int = 0

var _on_zoom_request: Callable = Callable()
var _on_resolve: Callable = Callable()
var _on_view_board: Callable = Callable()
var _pool_filter: Callable = Callable()


func _ready() -> void:
	visible = false
	z_index = 100
	_skip_btn.pressed.connect(_on_skip)
	_confirm_btn.pressed.connect(_on_confirm)
	_show_all_toggle.toggled.connect(_on_toggled)
	_stacked_toggle.toggled.connect(_on_toggled)
	_view_board_btn.pressed.connect(_on_view_board_pressed)
	if GameSettings.use_mobile_layout:
		_apply_mobile_sizing()


func _apply_mobile_sizing() -> void:
	for btn in [_skip_btn, _confirm_btn, _view_board_btn]:
		btn.custom_minimum_size.y = 55
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	for cb in [_show_all_toggle, _stacked_toggle]:
		cb.custom_minimum_size.y = 55
		cb.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	for path in [
		"CardSelectPanel/VBox/ContentContainer/PoolPanel/PoolVBox/ScrollContainer",
		"CardSelectPanel/VBox/ContentContainer/SelectionPanel/SelectionVBox/ScrollContainer",
	]:
		var sc: ScrollContainer = get_node_or_null(path)
		if sc:
			sc.scroll_deadzone = 40


func open(
	matching: Array,
	all_cards: Array,
	prompt: String,
	min_count: int,
	max_count: int,
	stacked: bool,
	on_zoom_request: Callable,
	on_resolve: Callable,
	on_view_board: Callable,
	pool_filter: Callable,
) -> void:
	_matching = matching.duplicate()
	_all_cards = all_cards.duplicate()
	_matching_ids.clear()
	for card_data in matching:
		_matching_ids[card_data.get("id", "")] = true
	_selected = []
	_min_count = min_count
	_max_count = max_count
	_on_zoom_request = on_zoom_request
	_on_resolve = on_resolve
	_on_view_board = on_view_board
	_pool_filter = pool_filter
	_prompt.text = prompt
	_show_all_toggle.set_pressed_no_signal(matching.is_empty())
	_stacked_toggle.set_pressed_no_signal(stacked)
	visible = true
	_refresh()


func reshow() -> void:
	visible = true


func close() -> void:
	visible = false
	_clear_grids()
	_matching.clear()
	_all_cards.clear()
	_matching_ids.clear()
	_selected.clear()
	closed.emit()


func _on_skip() -> void:
	visible = false
	if _on_resolve.is_valid():
		_on_resolve.call([])


func _on_confirm() -> void:
	var n := _selected.size()
	if n < _min_count or n > _max_count:
		return
	var picked := _selected.duplicate()
	visible = false
	if _on_resolve.is_valid():
		_on_resolve.call(picked)


func _on_toggled(_value: bool) -> void:
	stacked_toggled.emit(_stacked_toggle.button_pressed)
	_refresh()


func _on_view_board_pressed() -> void:
	visible = false
	if _on_view_board.is_valid():
		_on_view_board.call()


func _clear_grids() -> void:
	for child in _pool_grid.get_children():
		child.queue_free()
	for child in _selection_grid.get_children():
		child.queue_free()


func _refresh() -> void:
	_refresh_pool()
	_refresh_selection()
	_update_buttons()


func _get_pool() -> Array:
	# Strip already-selected cards from the visible pool by instance id.
	var show_all := _show_all_toggle.button_pressed
	var source: Array = _all_cards if show_all else _matching
	var sel_ids: Dictionary = {}
	for card in _selected:
		var id: String = card.get("id", "")
		sel_ids[id] = sel_ids.get(id, 0) + 1
	var pool: Array = []
	for card in source:
		var id: String = card.get("id", "")
		if sel_ids.get(id, 0) > 0:
			sel_ids[id] -= 1
		else:
			pool.append(card)
	return pool


func _refresh_pool() -> void:
	for child in _pool_grid.get_children():
		child.queue_free()
	var stacked := _stacked_toggle.button_pressed
	var show_all := _show_all_toggle.button_pressed
	var pool := _get_pool()
	var all_selectable: bool = not show_all
	var at_limit: bool = _selected.size() >= _max_count

	if stacked:
		var groups := CardGridUtils.group_cards(pool, _matching_ids)
		for group in groups:
			var card_data: Dictionary = group["card_data"]
			var count: int = group["count"]
			var is_match: bool = all_selectable or group["has_match"]
			var passes: bool = not _pool_filter.is_valid() or _pool_filter.call(card_data, _selected)
			var card := _make_pool_card(card_data, is_match and not at_limit and passes)
			_pool_grid.add_child(card)
			CardGridUtils.add_count_badge(card, count)
	else:
		for card_data in pool:
			var is_match: bool = all_selectable or _matching_ids.has(card_data.get("id", ""))
			var passes: bool = not _pool_filter.is_valid() or _pool_filter.call(card_data, _selected)
			var card := _make_pool_card(card_data, is_match and not at_limit and passes)
			_pool_grid.add_child(card)


func _make_pool_card(card_data: Dictionary, can_select: bool) -> Control:
	var card: Control = _CARD_SCENE.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	card.custom_minimum_size = _CARD_SIZE
	card.size = _CARD_SIZE
	card.drag_enabled = false
	if _on_zoom_request.is_valid():
		CardGridUtils.wire_gallery_card(card, _on_zoom_request)
	card.is_selectable = can_select
	card.click_on_release = true
	if can_select:
		card.card_clicked.connect(_on_pool_card_clicked)
	else:
		card.modulate = Color(0.5, 0.5, 0.5, 0.7)
	return card


func _refresh_selection() -> void:
	for child in _selection_grid.get_children():
		child.queue_free()
	for card_data in _selected:
		var card: Control = _CARD_SCENE.instantiate()
		if card.has_method("set_card_data_dict"):
			card.set_card_data_dict(card_data)
		card.custom_minimum_size = _CARD_SIZE
		card.size = _CARD_SIZE
		card.drag_enabled = false
		card.is_selectable = true
		card.click_on_release = true
		if _on_zoom_request.is_valid():
			CardGridUtils.wire_gallery_card(card, _on_zoom_request)
		card.card_clicked.connect(_on_selection_card_clicked)
		_selection_grid.add_child(card)
	_selection_label.text = tr("STR_GB_SELECTED_FMT").replace("{N}", str(_selected.size())).replace("{MAX}", str(_max_count))


func _update_buttons() -> void:
	var n := _selected.size()
	_confirm_btn.disabled = n < _min_count or n > _max_count
	_confirm_btn.text = tr("STR_GB_CONFIRM_COUNT_FMT").replace("{N}", str(n)).replace("{MAX}", str(_max_count))


func _on_pool_card_clicked(card: Control) -> void:
	var card_data: Dictionary = card.card_data if "card_data" in card else {}
	if card_data.is_empty() or _selected.size() >= _max_count:
		return
	# Match by template id; pick first matching pool entry that has a real id.
	var pool := _get_pool()
	var target_tid := CardUtils.base_id(card_data)
	for pool_card in pool:
		if CardUtils.base_id(pool_card) == target_tid and _matching_ids.has(pool_card.get("id", "")):
			_selected.append(pool_card)
			break
	_refresh()


func _on_selection_card_clicked(card: Control) -> void:
	var card_data: Dictionary = card.card_data if "card_data" in card else {}
	if card_data.is_empty():
		return
	var card_id: String = card_data.get("id", "")
	for i in range(_selected.size()):
		if _selected[i].get("id", "") == card_id:
			_selected.remove_at(i)
			break
	_refresh()
