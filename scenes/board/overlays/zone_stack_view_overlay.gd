extends ColorRect

## Read-only modal that shows the cards stacked in a single board zone or
## strategy slot, in the order they entered. Also reused by the
## "cards revealed" effect prompt — connect once to the `closed` signal
## and call `resolve_cards_revealed()` when it fires.
##
## No stacked toggle (zone stacks are inherently ordered, not multi-set).

signal closed

## Routes the "cards_revealed" effect prompt by default. The host scene's
## click-to-view-zone-stack flow uses `open()` directly, which doesn't
## involve the router.
@export var prompt_key: String = "cards_revealed"
@export var auto_register: bool = true

func _card_scene() -> PackedScene:
	return BoardModule.get_card_scene(self)

@onready var _title: Label = $ZoneStackViewPanel/VBox/TitleLabel
@onready var _grid: GridContainer = $ZoneStackViewPanel/VBox/ScrollContainer/CardGrid
@onready var _close_btn: Button = $ZoneStackViewPanel/VBox/CloseButton

var _cards: Array = []
var _on_zoom_request: Callable = Callable()


func _ready() -> void:
	visible = false
	z_index = 100
	_close_btn.pressed.connect(close)
	gui_input.connect(_on_background_input)
	if GameSettings.use_mobile_layout:
		_apply_mobile_sizing()
	if auto_register:
		var router := BoardModule.find_router(self)
		if router:
			router.register_handler(prompt_key, _on_router_show)
			closed.connect(_on_router_closed)


var _pending_resolve: Callable = Callable()


func _on_router_show(cards: Array, title: String, resolve_cb: Callable) -> void:
	var router := BoardModule.find_router(self)
	open(cards, title, router.card_zoom_request)
	_pending_resolve = resolve_cb


func _on_router_closed() -> void:
	if _pending_resolve.is_valid():
		var cb := _pending_resolve
		_pending_resolve = Callable()
		cb.call()


func _apply_mobile_sizing() -> void:
	_close_btn.custom_minimum_size.y = 55
	_close_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	var sc: ScrollContainer = $ZoneStackViewPanel/VBox/ScrollContainer
	sc.scroll_deadzone = 40


func open(cards: Array, title: String, on_zoom_request: Callable) -> void:
	_cards = cards.duplicate()
	_title.text = title
	_on_zoom_request = on_zoom_request
	visible = true
	_render_grid()


func close() -> void:
	visible = false
	_clear_grid()
	closed.emit()


func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var panel_rect := ($ZoneStackViewPanel as Control).get_global_rect()
		if not panel_rect.has_point(event.global_position):
			close()


func _clear_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()


func _render_grid() -> void:
	_clear_grid()
	for card_data in _cards:
		var card: Control = _card_scene().instantiate()
		if card.has_method("set_card_data_dict"):
			card.set_card_data_dict(card_data)
		card.is_selectable = false
		card.drag_enabled = false
		if _on_zoom_request.is_valid():
			CardGridUtils.wire_gallery_card(card, _on_zoom_request)
		_grid.add_child(card)
