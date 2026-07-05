class_name DeckSearchOverlayUI
extends ColorRect

## Deck-search prompt overlay: pick one matching card from a card grid
## (optionally skippable), with show-all and stacked gallery toggles and a
## "view board" stash. Registered with EffectUIRouter as the "deck_search"
## handler; the resolve callback passed to show_prompt() handles the
## host-vs-client routing.

const CARD_SCENE: PackedScene = preload("res://scenes/cards/Card.tscn")

@onready var _prompt: Label = $DeckSearchPanel/VBox/PromptLabel
@onready var _grid: GridContainer = $DeckSearchPanel/VBox/ScrollContainer/CardGrid
@onready var _skip: Button = $DeckSearchPanel/VBox/SkipButton
@onready var _show_all: CheckButton = $DeckSearchPanel/VBox/ToggleRow/ShowAllToggle
@onready var _stacked: CheckButton = $DeckSearchPanel/VBox/ToggleRow/StackedToggle
@onready var _view_board: Button = $DeckSearchPanel/VBox/ToggleRow/ViewBoardButton

var _router: EffectUIRouter

var _matching: Array = []
var _all: Array = []
var _matching_ids: Dictionary = {} # card id -> true, for highlighting
var _resolve_cb: Callable = Callable()


func _ready() -> void:
	visible = false
	z_index = 100
	_router = get_node_or_null("../GameSession/EffectUIRouter")
	_skip.pressed.connect(_on_skip)
	_show_all.toggled.connect(_on_toggled)
	_stacked.toggled.connect(_on_toggled)
	_view_board.pressed.connect(_on_view_board)


## Router handler entry point — `prompt` arrives already translated.
func show_prompt(matching: Array, all_cards: Array, prompt: String, allow_skip: bool, resolve_cb: Callable) -> void:
	OverlayGridUtil.ensure_full_rect(self)
	_matching = matching
	_all = all_cards
	_resolve_cb = resolve_cb
	_matching_ids.clear()
	for card_data in matching:
		_matching_ids[card_data.get("id", "")] = true

	_prompt.text = prompt
	_skip.visible = allow_skip
	_show_all.set_pressed_no_signal(matching.is_empty())
	_stacked.set_pressed_no_signal(_router.match_stacked_view if _router else true)
	visible = true

	_refresh_grid()


## ESC/back handling — skip only when the prompt is skippable.
func try_skip() -> void:
	if visible and _skip.visible:
		_on_skip()


func _refresh_grid() -> void:
	var show_all := _show_all.button_pressed
	var stacked := _stacked.button_pressed
	var cards: Array = _all if show_all else _matching
	var all_selectable: bool = not show_all

	var zoom: Callable = _router.card_zoom_request if _router else Callable()
	OverlayGridUtil.clear_grid(_grid, _on_card_clicked)

	if stacked:
		var groups := OverlayGridUtil.group_cards(cards, _matching_ids)
		for group in groups:
			var card_data: Dictionary = group["card_data"]
			var count: int = group["count"]
			var card: Control = CARD_SCENE.instantiate()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(card_data)
			card.drag_enabled = false
			OverlayGridUtil.set_gallery_hover(card, zoom)
			var is_match: bool = all_selectable or group["has_match"]
			card.is_selectable = is_match
			if is_match:
				card.card_clicked.connect(_on_card_clicked)
			else:
				card.modulate = Color(0.5, 0.5, 0.5, 0.7)
			card.card_right_clicked.connect(_on_card_zoom)
			_grid.add_child(card)
			OverlayGridUtil.add_count_badge(card, count)
	else:
		for card_data in cards:
			var card: Control = CARD_SCENE.instantiate()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(card_data)
			card.drag_enabled = false
			OverlayGridUtil.set_gallery_hover(card, zoom)
			var is_match: bool = all_selectable or _matching_ids.has(card_data.get("id", ""))
			card.is_selectable = is_match
			if is_match:
				card.card_clicked.connect(_on_card_clicked)
			else:
				card.modulate = Color(0.5, 0.5, 0.5, 0.7)
			card.card_right_clicked.connect(_on_card_zoom)
			_grid.add_child(card)


func _on_toggled(_value: bool) -> void:
	if _router:
		_router.match_stacked_view = _stacked.button_pressed
	_refresh_grid()


func _on_view_board() -> void:
	visible = false
	if _router and _router.on_view_board_request.is_valid():
		_router.on_view_board_request.call(self)


## Label data for the minimize chip shown while this overlay is hidden.
func get_minimize_info() -> Dictionary:
	return {"title": _prompt.text, "count": _matching.size()}


func _on_card_zoom(card: Control) -> void:
	if _router and _router.card_zoom_request.is_valid() and "card_data" in card:
		_router.card_zoom_request.call(card.card_data, 0)


func _on_card_clicked(card: Control) -> void:
	var selected: Dictionary = card.card_data if "card_data" in card else {}
	var cb := _resolve_cb
	_hide()
	if cb.is_valid():
		cb.call(selected)


func _on_skip() -> void:
	var cb := _resolve_cb
	_hide()
	if cb.is_valid():
		cb.call({})


func _hide() -> void:
	visible = false
	OverlayGridUtil.clear_grid(_grid, _on_card_clicked)
	_matching = []
	_all = []
	_matching_ids.clear()
	_resolve_cb = Callable()
