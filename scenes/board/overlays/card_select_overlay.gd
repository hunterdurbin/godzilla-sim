class_name CardSelectOverlayUI
extends ColorRect

## Card pool select overlay: move cards between a pool (left) and a
## selection area (right) until exactly min..max are picked, then confirm.
## Registered with EffectUIRouter as the "card_select" handler.

const CARD_SCENE: PackedScene = preload("res://scenes/cards/Card.tscn")
const CARD_SIZE := Vector2(120, 168)

@onready var _prompt: Label = $CardSelectPanel/VBox/PromptLabel
@onready var _pool_grid: GridContainer = $CardSelectPanel/VBox/ContentContainer/PoolPanel/PoolVBox/ScrollContainer/PoolGrid
@onready var _selection_grid: GridContainer = $CardSelectPanel/VBox/ContentContainer/SelectionPanel/SelectionVBox/ScrollContainer/SelectionGrid
@onready var _selection_label: Label = $CardSelectPanel/VBox/ContentContainer/SelectionPanel/SelectionVBox/SelectionLabel
@onready var _show_all: CheckButton = $CardSelectPanel/VBox/ToggleRow/ShowAllToggle
@onready var _stacked: CheckButton = $CardSelectPanel/VBox/ToggleRow/StackedToggle
@onready var _view_board: Button = $CardSelectPanel/VBox/ToggleRow/ViewBoardButton
@onready var _skip: Button = $CardSelectPanel/VBox/ButtonRow/SkipButton
@onready var _confirm: Button = $CardSelectPanel/VBox/ButtonRow/ConfirmButton

var _router: EffectUIRouter

var _matching: Array = []
var _all: Array = []
var _matching_ids: Dictionary = {} # card id -> true
var _selected: Array[Dictionary] = []
var _min_count: int = 0
var _max_count: int = 0
var _resolve_cb: Callable = Callable()


func _ready() -> void:
	visible = false
	z_index = 100
	_router = get_node_or_null("../GameSession/EffectUIRouter")
	_skip.pressed.connect(_on_skip)
	_confirm.pressed.connect(_on_confirm)
	_show_all.toggled.connect(_on_toggled)
	_stacked.toggled.connect(_on_toggled)
	_view_board.pressed.connect(_on_view_board)


## Router handler entry point — `prompt` arrives already translated.
func show_prompt(matching: Array, all_cards: Array, prompt: String, min_count: int, max_count: int, resolve_cb: Callable) -> void:
	OverlayGridUtil.ensure_full_rect(self)
	_matching = matching
	_all = all_cards
	_matching_ids.clear()
	for card_data in matching:
		_matching_ids[card_data.get("id", "")] = true
	_selected = []
	_min_count = min_count
	_max_count = max_count
	_resolve_cb = resolve_cb

	_prompt.text = prompt
	_show_all.set_pressed_no_signal(matching.is_empty())
	_stacked.set_pressed_no_signal(_router.match_stacked_view if _router else true)
	visible = true

	_refresh()


## ESC/back handling — pool select prompts are always skippable.
func try_skip() -> void:
	if visible:
		_on_skip()


func _pool_filter() -> Callable:
	# Optional per-effect pool filter, host side only (clients see no filter —
	# pre-existing behavior; the host validates the resolution anyway).
	if _router and _router.session and _router.session.effect_handler:
		return _router.session.effect_handler._card_select_pool_filter
	return Callable()


func _refresh() -> void:
	_refresh_pool()
	_refresh_selection()
	_update_buttons()


func _get_pool() -> Array:
	var source: Array = _all if _show_all.button_pressed else _matching
	# Remove selected cards from pool by unique ID (count-aware)
	var selected_ids: Dictionary = {}
	for card in _selected:
		var id: String = card.get("id", "")
		selected_ids[id] = selected_ids.get(id, 0) + 1
	var pool: Array = []
	for card in source:
		var id: String = card.get("id", "")
		if selected_ids.get(id, 0) > 0:
			selected_ids[id] -= 1
		else:
			pool.append(card)
	return pool


func _refresh_pool() -> void:
	var stacked := _stacked.button_pressed
	var show_all := _show_all.button_pressed
	var pool := _get_pool()
	var all_selectable: bool = not show_all
	var at_limit: bool = _selected.size() >= _max_count
	var pool_filter := _pool_filter()
	var zoom: Callable = _router.card_zoom_request if _router else Callable()

	OverlayGridUtil.clear_grid(_pool_grid, _on_pool_clicked)

	if stacked:
		var groups := OverlayGridUtil.group_cards(pool, _matching_ids)
		for group in groups:
			var card_data: Dictionary = group["card_data"]
			var count: int = group["count"]
			var card: Control = _make_card(card_data, zoom)
			var is_match: bool = all_selectable or group["has_match"]
			var passes_filter: bool = not pool_filter.is_valid() or pool_filter.call(card_data, _selected)
			var can_select: bool = is_match and not at_limit and passes_filter
			card.is_selectable = can_select
			if can_select:
				card.card_clicked.connect(_on_pool_clicked)
			else:
				card.modulate = Color(0.5, 0.5, 0.5, 0.7)
			_pool_grid.add_child(card)
			OverlayGridUtil.add_count_badge(card, count)
	else:
		for card_data in pool:
			var card: Control = _make_card(card_data, zoom)
			var is_match: bool = all_selectable or _matching_ids.has(card_data.get("id", ""))
			var passes_filter: bool = not pool_filter.is_valid() or pool_filter.call(card_data, _selected)
			var can_select: bool = is_match and not at_limit and passes_filter
			card.is_selectable = can_select
			if can_select:
				card.card_clicked.connect(_on_pool_clicked)
			else:
				card.modulate = Color(0.5, 0.5, 0.5, 0.7)
			_pool_grid.add_child(card)
	OverlayGridUtil.wire_grid_focus(_pool_grid)


func _make_card(card_data: Dictionary, zoom: Callable) -> Control:
	var card: Control = CARD_SCENE.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.drag_enabled = false
	card.click_on_release = true
	OverlayGridUtil.set_gallery_hover(card, zoom)
	card.card_right_clicked.connect(_on_card_zoom)
	return card


func _on_card_zoom(card: Control) -> void:
	if _router and _router.card_zoom_request.is_valid() and "card_data" in card:
		_router.card_zoom_request.call(card.card_data, 0)


func _refresh_selection() -> void:
	OverlayGridUtil.clear_grid(_selection_grid, _on_selection_clicked)
	var zoom: Callable = _router.card_zoom_request if _router else Callable()
	for card_data in _selected:
		var card: Control = _make_card(card_data, zoom)
		card.is_selectable = true
		card.card_clicked.connect(_on_selection_clicked)
		_selection_grid.add_child(card)

	_selection_label.text = tr("STR_GB_SELECTED_FMT").replace("{N}", str(_selected.size())).replace("{MAX}", str(_max_count))


func _update_buttons() -> void:
	var count := _selected.size()
	_confirm.disabled = count < _min_count or count > _max_count
	_confirm.text = tr("STR_GB_CONFIRM_COUNT_FMT").replace("{N}", str(count)).replace("{MAX}", str(_max_count))


func _on_pool_clicked(card: Control) -> void:
	var card_data: Dictionary = card.card_data if "card_data" in card else {}
	if card_data.is_empty() or _selected.size() >= _max_count:
		return

	var pool := _get_pool()
	var target_tid := OverlayGridUtil.get_card_template_id(card_data)
	for pool_card in pool:
		if OverlayGridUtil.get_card_template_id(pool_card) == target_tid and _matching_ids.has(pool_card.get("id", "")):
			_selected.append(pool_card)
			break

	_refresh()


func _on_selection_clicked(card: Control) -> void:
	var card_data: Dictionary = card.card_data if "card_data" in card else {}
	if card_data.is_empty():
		return

	var card_id: String = card_data.get("id", "")
	for i in range(_selected.size()):
		if _selected[i].get("id", "") == card_id:
			_selected.remove_at(i)
			break

	_refresh()


func _on_toggled(_value: bool) -> void:
	if _router:
		_router.match_stacked_view = _stacked.button_pressed
	_refresh()


func _on_view_board() -> void:
	visible = false
	if _router and _router.on_view_board_request.is_valid():
		_router.on_view_board_request.call(self)


## Label data for the minimize chip shown while this overlay is hidden.
func get_minimize_info() -> Dictionary:
	return {"title": _prompt.text, "count": _matching.size()}


func _on_skip() -> void:
	var cb := _resolve_cb
	_hide()
	if cb.is_valid():
		cb.call([])


func _on_confirm() -> void:
	var sel_count := _selected.size()
	if sel_count < _min_count or sel_count > _max_count:
		return
	var selected := _selected.duplicate()
	var cb := _resolve_cb
	_hide()
	if cb.is_valid():
		cb.call(selected)


func _hide() -> void:
	visible = false
	OverlayGridUtil.clear_grid(_pool_grid, _on_pool_clicked)
	OverlayGridUtil.clear_grid(_selection_grid, _on_selection_clicked)
	_matching = []
	_all = []
	_matching_ids.clear()
	_selected = []
	_resolve_cb = Callable()
