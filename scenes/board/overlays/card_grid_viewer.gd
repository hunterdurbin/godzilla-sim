class_name CardGridViewerUI
extends ColorRect

## Shared script for the passive card-grid viewer overlays (discard pile,
## monster deck, zone stack). Shows a read-only stacked/flat card gallery
## with a title, optional stacked toggle, and close button; clicking the
## dimmed background also closes.
##
## Two special modes layer on top for specific viewers:
##  - rank-up selection (monster deck viewer): mandatory pick of a monster,
##    registered with EffectUIRouter as the "monster_rankup" handler.
##  - cards revealed (zone stack viewer): dismissable reveal whose close
##    resolves the effect engine, registered as "cards_revealed".

const CARD_SCENE: PackedScene = preload("res://scenes/cards/Card.tscn")

## Panel child name differs per viewer scene ("DiscardViewPanel", ...).
@export var panel_name: String = "Panel"
## Shown in the grid when there are no cards to display ("" = show nothing).
@export var empty_text_key: String = ""

var _router: EffectUIRouter
var _title: Label
var _grid: GridContainer
var _close: Button
var _stacked: CheckButton # null when the viewer has no stacked toggle

var cards: Array[Dictionary] = []

# Rank-up selection mode (monster deck viewer)
var rankup_selecting: bool = false
var _rankup_resolve: Callable = Callable()

# Cards-revealed mode (zone stack viewer)
var _revealed_resolve: Callable = Callable()
var _revealed_active: bool = false


func _ready() -> void:
	visible = false
	z_index = 100
	_router = get_node_or_null("../GameSession/EffectUIRouter")
	var vbox := get_node(panel_name + "/VBox")
	_title = vbox.get_node("TitleLabel")
	_grid = vbox.get_node("ScrollContainer/CardGrid")
	_close = vbox.get_node("CloseButton")
	_stacked = vbox.get_node_or_null("StackedToggle")
	_close.pressed.connect(try_close)
	gui_input.connect(_on_background_clicked)
	if _stacked:
		_stacked.toggled.connect(_on_stacked_toggled)


## Passive view of a card list with a pre-translated title.
func show_cards(p_cards: Array, title: String) -> void:
	cards.assign(p_cards)
	_title.text = title
	if _stacked:
		_stacked.set_pressed_no_signal(_router.match_stacked_view if _router else true)
	visible = true
	_refresh()


## Mandatory rank-up pick (monster deck viewer). Close/stacked controls are
## hidden until resolved; ESC and background clicks are refused.
func show_rankup(monsters: Array, valid_indices: Array[int], prompt: String, resolve_cb: Callable) -> void:
	rankup_selecting = true
	_rankup_resolve = resolve_cb
	_title.text = prompt
	_close.visible = false
	if _stacked:
		_stacked.visible = false

	for child in _grid.get_children():
		child.queue_free()

	var zoom: Callable = _router.card_zoom_request if _router else Callable()
	for i in range(monsters.size()):
		var card_data: Dictionary = monsters[i]
		var card: Control = CARD_SCENE.instantiate()
		if card.has_method("set_card_data_dict"):
			card.set_card_data_dict(card_data)
		card.drag_enabled = false
		OverlayGridUtil.set_gallery_hover(card, zoom)
		if i in valid_indices:
			card.is_selectable = true
			card.card_clicked.connect(_on_rankup_card_clicked.bind(i))
		else:
			card.is_selectable = false
			card.modulate = Color(0.5, 0.5, 0.5, 1.0)
		card.card_right_clicked.connect(_on_card_zoom)
		_grid.add_child(card)

	visible = true


## Dismissable reveal (zone stack viewer): closing resolves the effect.
func show_revealed(p_cards: Array, title: String, resolve_cb: Callable) -> void:
	_revealed_active = true
	_revealed_resolve = resolve_cb
	cards.assign(p_cards)
	_title.text = tr("STR_GB_TITLE_COUNT_FMT").replace("{TITLE}", title).replace("{C}", str(cards.size()))
	visible = true
	_refresh()


## Close request (button, ESC, background click). Refused during the
## mandatory rank-up pick; resolves the cards-revealed effect if active.
func try_close() -> void:
	if rankup_selecting:
		return
	visible = false
	for child in _grid.get_children():
		child.queue_free()
	cards.clear()
	if _revealed_active:
		_revealed_active = false
		var cb := _revealed_resolve
		_revealed_resolve = Callable()
		if cb.is_valid():
			cb.call()


func _refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()

	if cards.is_empty():
		if not empty_text_key.is_empty():
			var empty_label := Label.new()
			empty_label.text = tr(empty_text_key)
			empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_grid.add_child(empty_label)
		return

	var zoom: Callable = _router.card_zoom_request if _router else Callable()
	var stacked: bool = _stacked != null and _stacked.button_pressed
	if stacked:
		var groups := OverlayGridUtil.group_cards(cards)
		for group in groups:
			var card := _make_card(group["card_data"], zoom)
			_grid.add_child(card)
			OverlayGridUtil.add_count_badge(card, group["count"])
	else:
		for card_data in cards:
			_grid.add_child(_make_card(card_data, zoom))


func _make_card(card_data: Dictionary, zoom: Callable) -> Control:
	var card: Control = CARD_SCENE.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	card.is_selectable = false
	card.drag_enabled = false
	OverlayGridUtil.set_gallery_hover(card, zoom)
	card.card_right_clicked.connect(_on_card_zoom)
	return card


func _on_card_zoom(card: Control) -> void:
	if _router and _router.card_zoom_request.is_valid() and "card_data" in card:
		_router.card_zoom_request.call(card.card_data, 0)


func _on_stacked_toggled(_value: bool) -> void:
	if _router:
		_router.match_stacked_view = _stacked.button_pressed
	_refresh()


func _on_background_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		try_close()


func _on_rankup_card_clicked(_card: Control, index: int) -> void:
	if not rankup_selecting:
		return
	var cb := _rankup_resolve
	cleanup_rankup()
	if cb.is_valid():
		cb.call(index)


## Tear down rank-up mode (also called by the board's rematch reset).
func cleanup_rankup() -> void:
	rankup_selecting = false
	_rankup_resolve = Callable()
	visible = false
	_close.visible = true
	if _stacked:
		_stacked.visible = true
	for child in _grid.get_children():
		child.queue_free()
