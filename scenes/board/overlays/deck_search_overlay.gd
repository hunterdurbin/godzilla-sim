extends ColorRect

## Deck-search effect prompt: shows matching cards (with "Show all" toggle to
## see the rest of the deck), stacked toggle, and an optional skip button.
## Clicking a matching card resolves the effect with that card; clicking skip
## (or pressing ESC if allow_skip) resolves with `{}`.
##
## Public API:
##   open(matching, all_cards, prompt, allow_skip, stacked, on_zoom_request,
##        on_resolve, on_view_board)
##   close()                    -- ESC / skip
##   signal stacked_toggled(stacked)
##   signal closed
##   skip_visible() -> bool     -- used by the host to gate ESC dismissal
##
## `on_resolve` is invoked as `Callable(selected: Dictionary)`. Empty dict
## means the player skipped.
## `on_view_board` is invoked when the user wants to peek at the board —
## the host hides this overlay, shows the "show cards" button, and re-shows
## on demand. The overlay just signals; layout-orchestration stays in host.

signal stacked_toggled(stacked: bool)
signal closed

## Drop this scene anywhere under a GameBoard root and it self-registers
## with the EffectUIRouter using `prompt_key`. To override the default
## handler with a custom variant, place a second overlay scene with the
## same `prompt_key` — last-registered wins. Set `auto_register = false`
## if the host scene wants explicit control.
@export var prompt_key: String = "deck_search"
@export var auto_register: bool = true

const _CARD_SCENE := preload("res://scenes/cards/Card.tscn")

@onready var _prompt: Label = $DeckSearchPanel/VBox/PromptLabel
@onready var _show_all_toggle: CheckButton = $DeckSearchPanel/VBox/ToggleRow/ShowAllToggle
@onready var _stacked_toggle: CheckButton = $DeckSearchPanel/VBox/ToggleRow/StackedToggle
@onready var _view_board_btn: Button = $DeckSearchPanel/VBox/ToggleRow/ViewBoardButton
@onready var _grid: GridContainer = $DeckSearchPanel/VBox/ScrollContainer/CardGrid
@onready var _skip_btn: Button = $DeckSearchPanel/VBox/SkipButton

var _matching: Array = []
var _all_cards: Array = []
var _matching_ids: Dictionary = {}

var _on_zoom_request: Callable = Callable()
var _on_resolve: Callable = Callable()
var _on_view_board: Callable = Callable()


func _ready() -> void:
	visible = false
	z_index = 100
	_skip_btn.pressed.connect(_on_skip)
	_show_all_toggle.toggled.connect(_on_toggled)
	_stacked_toggle.toggled.connect(_on_toggled)
	_view_board_btn.pressed.connect(_on_view_board_pressed)
	if GameSettings.use_mobile_layout:
		_apply_mobile_sizing()
	if auto_register:
		var router := BoardModule.find_router(self)
		if router:
			router.register_handler(prompt_key, _on_router_show)


func _on_router_show(matching: Array, all_cards: Array, prompt: String, allow_skip: bool, resolve_cb: Callable) -> void:
	var router := BoardModule.find_router(self)
	var stacked := router.match_stacked_view if router else true
	open(matching, all_cards, prompt, allow_skip, stacked, router.card_zoom_request, resolve_cb, _ask_host_to_view_board)


func _ask_host_to_view_board() -> void:
	var router := BoardModule.find_router(self)
	if router and router.on_view_board_request.is_valid():
		router.on_view_board_request.call(self)


func _apply_mobile_sizing() -> void:
	for btn in [_skip_btn, _view_board_btn]:
		btn.custom_minimum_size.y = 55
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	for cb in [_show_all_toggle, _stacked_toggle]:
		cb.custom_minimum_size.y = 55
		cb.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	var sc: ScrollContainer = $DeckSearchPanel/VBox/ScrollContainer
	sc.scroll_deadzone = 40


func skip_visible() -> bool:
	return _skip_btn.visible


func open(
	matching: Array,
	all_cards: Array,
	prompt: String,
	allow_skip: bool,
	stacked: bool,
	on_zoom_request: Callable,
	on_resolve: Callable,
	on_view_board: Callable,
) -> void:
	_matching = matching.duplicate()
	_all_cards = all_cards.duplicate()
	_matching_ids.clear()
	for card_data in matching:
		_matching_ids[card_data.get("id", "")] = true
	_on_zoom_request = on_zoom_request
	_on_resolve = on_resolve
	_on_view_board = on_view_board
	_prompt.text = prompt
	_skip_btn.visible = allow_skip
	_show_all_toggle.set_pressed_no_signal(matching.is_empty())
	_stacked_toggle.set_pressed_no_signal(stacked)
	visible = true
	_refresh_grid()


## Re-show after a "view board" detour. Caller stashed our visibility while
## the player peeked at the board.
func reshow() -> void:
	visible = true


func close() -> void:
	visible = false
	_clear_grid()
	_matching.clear()
	_all_cards.clear()
	_matching_ids.clear()
	closed.emit()


func _on_toggled(_value: bool) -> void:
	stacked_toggled.emit(_stacked_toggle.button_pressed)
	_refresh_grid()


func _on_skip() -> void:
	visible = false
	if _on_resolve.is_valid():
		_on_resolve.call({})


func _on_view_board_pressed() -> void:
	visible = false
	if _on_view_board.is_valid():
		_on_view_board.call()


func _on_card_clicked(card: Control) -> void:
	var selected: Dictionary = card.card_data if "card_data" in card else {}
	visible = false
	if _on_resolve.is_valid():
		_on_resolve.call(selected)


func _clear_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()


func _refresh_grid() -> void:
	_clear_grid()
	var show_all := _show_all_toggle.button_pressed
	var stacked := _stacked_toggle.button_pressed
	var cards: Array = _all_cards if show_all else _matching
	var all_selectable: bool = not show_all

	if stacked:
		var groups := CardGridUtils.group_cards(cards, _matching_ids)
		for group in groups:
			var card_data: Dictionary = group["card_data"]
			var count: int = group["count"]
			var card := _make_card(card_data, all_selectable or group["has_match"])
			_grid.add_child(card)
			CardGridUtils.add_count_badge(card, count)
	else:
		for card_data in cards:
			var is_match: bool = all_selectable or _matching_ids.has(card_data.get("id", ""))
			var card := _make_card(card_data, is_match)
			_grid.add_child(card)


func _make_card(card_data: Dictionary, is_selectable: bool) -> Control:
	var card: Control = _CARD_SCENE.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	card.drag_enabled = false
	if _on_zoom_request.is_valid():
		CardGridUtils.wire_gallery_card(card, _on_zoom_request)
	card.is_selectable = is_selectable
	if is_selectable:
		card.card_clicked.connect(_on_card_clicked)
	else:
		card.modulate = Color(0.5, 0.5, 0.5, 0.7)
	return card
