extends ColorRect

## Modal that shows a player's monster deck.
##
## Two operating modes share the same node tree:
##   open_view(cards, title, stacked, on_zoom)
##     — read-only browser, dismissible (close button + click-outside).
##   open_rankup(monsters, valid_indices, title, on_zoom, on_select)
##     — mandatory rank-up selection. Close + stacked toggle hidden;
##       cards at `valid_indices` are clickable, others greyed out;
##       `on_select` is called as `Callable(index: int)` when the player
##       picks a candidate.
##
## Stays close-blocked while in rank-up mode (rule: rank-up is mandatory).

signal stacked_toggled(stacked: bool)
signal closed

## Auto-routes the "monster_rankup" effect prompt. The user-initiated
## "view monster deck" flow uses `open_view()` directly without the router.
@export var prompt_key: String = "monster_rankup"
@export var auto_register: bool = true

const _CARD_SCENE := preload("res://scenes/cards/Card.tscn")

@onready var _title: Label = $MonsterDeckViewPanel/VBox/TitleLabel
@onready var _stacked_toggle: CheckButton = $MonsterDeckViewPanel/VBox/StackedToggle
@onready var _grid: GridContainer = $MonsterDeckViewPanel/VBox/ScrollContainer/CardGrid
@onready var _close_btn: Button = $MonsterDeckViewPanel/VBox/CloseButton

var _cards: Array = []
var _on_zoom_request: Callable = Callable()
var _on_select: Callable = Callable()
var _valid_indices: Array[int] = []
var _mandatory: bool = false


func _ready() -> void:
	visible = false
	z_index = 100
	_close_btn.pressed.connect(close)
	gui_input.connect(_on_background_input)
	_stacked_toggle.toggled.connect(_on_stacked_toggled)
	if GameSettings.use_mobile_layout:
		_apply_mobile_sizing()
	if auto_register:
		var router := BoardModule.find_router(self)
		if router:
			router.register_handler(prompt_key, _on_router_show)


func _on_router_show(monsters: Array, valid_indices: Array[int], prompt: String, resolve_cb: Callable) -> void:
	var router := BoardModule.find_router(self)
	open_rankup(monsters, valid_indices, prompt, router.card_zoom_request, resolve_cb)


func _apply_mobile_sizing() -> void:
	_close_btn.custom_minimum_size.y = 55
	_close_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_stacked_toggle.custom_minimum_size.y = 55
	_stacked_toggle.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	var sc: ScrollContainer = $MonsterDeckViewPanel/VBox/ScrollContainer
	sc.scroll_deadzone = 40


## Read-only viewer.
func open_view(cards: Array, title: String, stacked: bool, on_zoom_request: Callable) -> void:
	_cards = cards.duplicate()
	_title.text = title
	_stacked_toggle.set_pressed_no_signal(stacked)
	_on_zoom_request = on_zoom_request
	_on_select = Callable()
	_valid_indices.clear()
	_mandatory = false
	_close_btn.visible = true
	_stacked_toggle.visible = true
	visible = true
	_refresh_view_grid()


## Mandatory rank-up selection.
func open_rankup(monsters: Array, valid_indices: Array[int], title: String, on_zoom_request: Callable, on_select: Callable) -> void:
	_cards = monsters.duplicate()
	_title.text = title
	_on_zoom_request = on_zoom_request
	_on_select = on_select
	_valid_indices = valid_indices.duplicate()
	_mandatory = true
	_close_btn.visible = false
	_stacked_toggle.visible = false
	visible = true
	_render_rankup_grid()


## Force-close the rank-up mode (called by host after the player resolves).
func dismiss_rankup() -> void:
	_mandatory = false
	close()


func close() -> void:
	if _mandatory:
		return
	visible = false
	_clear_grid()
	closed.emit()


func _on_stacked_toggled(value: bool) -> void:
	stacked_toggled.emit(value)
	_refresh_view_grid()


func _on_background_input(event: InputEvent) -> void:
	if _mandatory:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var panel_rect := ($MonsterDeckViewPanel as Control).get_global_rect()
		if not panel_rect.has_point(event.global_position):
			close()


func _clear_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()


func _refresh_view_grid() -> void:
	_clear_grid()
	if _cards.is_empty():
		var empty := Label.new()
		empty.text = tr("STR_GB_NO_MONSTER_DECK")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grid.add_child(empty)
		return

	if _stacked_toggle.button_pressed:
		var groups := CardGridUtils.group_cards(_cards)
		for group in groups:
			var card := _make_view_card(group["card_data"])
			_grid.add_child(card)
			CardGridUtils.add_count_badge(card, group["count"])
	else:
		for card_data in _cards:
			var card := _make_view_card(card_data)
			_grid.add_child(card)


func _make_view_card(card_data: Dictionary) -> Control:
	var card: Control = _CARD_SCENE.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	card.is_selectable = false
	card.drag_enabled = false
	if _on_zoom_request.is_valid():
		CardGridUtils.wire_gallery_card(card, _on_zoom_request)
	return card


func _render_rankup_grid() -> void:
	_clear_grid()
	for i in range(_cards.size()):
		var card_data: Dictionary = _cards[i]
		var card: Control = _CARD_SCENE.instantiate()
		if card.has_method("set_card_data_dict"):
			card.set_card_data_dict(card_data)
		card.drag_enabled = false
		if _on_zoom_request.is_valid():
			CardGridUtils.wire_gallery_card(card, _on_zoom_request)

		if i in _valid_indices:
			card.is_selectable = true
			card.card_clicked.connect(_on_rankup_card_clicked.bind(i))
		else:
			card.is_selectable = false
			card.modulate = Color(0.5, 0.5, 0.5, 1.0)

		_grid.add_child(card)


func _on_rankup_card_clicked(_card: Control, index: int) -> void:
	if _on_select.is_valid():
		_on_select.call(index)
