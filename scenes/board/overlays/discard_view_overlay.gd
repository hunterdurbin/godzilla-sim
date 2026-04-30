extends ColorRect

## Read-only modal that shows the contents of a discard pile.
## First overlay extracted out of game_board.gd (proof-of-pattern).
##
## Public contract:
##   open(cards, title, stacked, on_zoom_request)
##   signal stacked_toggled(stacked)
##   signal closed
##
## Cards are provided by the caller (game_board hands a duplicate array of
## PlayerState.discard_pile so the overlay never reaches into game state).
## `on_zoom_request` is the Callable invoked when the user right-clicks /
## long-presses / double-clicks a card to zoom it — the host scene decides
## how to render the zoom (existing CardZoomOverlay, a future scene, etc.).

signal stacked_toggled(stacked: bool)
signal closed

const _CARD_SCENE := preload("res://scenes/cards/Card.tscn")

@onready var _title: Label = $DiscardViewPanel/VBox/TitleLabel
@onready var _stacked_toggle: CheckButton = $DiscardViewPanel/VBox/StackedToggle
@onready var _grid: GridContainer = $DiscardViewPanel/VBox/ScrollContainer/CardGrid
@onready var _close_btn: Button = $DiscardViewPanel/VBox/CloseButton

var _cards: Array = []
var _on_zoom_request: Callable = Callable()


func _ready() -> void:
	visible = false
	z_index = 100
	_close_btn.pressed.connect(close)
	gui_input.connect(_on_background_input)
	_stacked_toggle.toggled.connect(_on_stacked_toggled)
	if GameSettings.use_mobile_layout:
		_apply_mobile_sizing()


func _apply_mobile_sizing() -> void:
	_close_btn.custom_minimum_size.y = 55
	_close_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_stacked_toggle.custom_minimum_size.y = 55
	_stacked_toggle.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	var sc: ScrollContainer = $DiscardViewPanel/VBox/ScrollContainer
	sc.scroll_deadzone = 40


func open(cards: Array, title: String, stacked: bool, on_zoom_request: Callable) -> void:
	_cards = cards.duplicate()
	_title.text = title
	_stacked_toggle.set_pressed_no_signal(stacked)
	_on_zoom_request = on_zoom_request
	visible = true
	_refresh_grid()


func close() -> void:
	visible = false
	_clear_grid()
	closed.emit()


func _on_stacked_toggled(value: bool) -> void:
	stacked_toggled.emit(value)
	_refresh_grid()


func _on_background_input(event: InputEvent) -> void:
	# Click outside the panel closes the overlay.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var panel_rect := ($DiscardViewPanel as Control).get_global_rect()
		if not panel_rect.has_point(event.global_position):
			close()


func _clear_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()


func _refresh_grid() -> void:
	_clear_grid()
	if _cards.is_empty():
		var empty := Label.new()
		empty.text = tr("STR_GB_NO_DISCARD")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grid.add_child(empty)
		return

	if _stacked_toggle.button_pressed:
		var groups := CardGridUtils.group_cards(_cards)
		for group in groups:
			var card := _make_card(group["card_data"])
			_grid.add_child(card)
			CardGridUtils.add_count_badge(card, group["count"])
	else:
		for card_data in _cards:
			var card := _make_card(card_data)
			_grid.add_child(card)


func _make_card(card_data: Dictionary) -> Control:
	var card: Control = _CARD_SCENE.instantiate()
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(card_data)
	card.is_selectable = false
	card.drag_enabled = false
	if _on_zoom_request.is_valid():
		CardGridUtils.wire_gallery_card(card, _on_zoom_request)
	return card
