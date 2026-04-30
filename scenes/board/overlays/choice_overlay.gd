class_name ChoiceOverlay
extends Object

## Lightweight controller for the standby-ability ordering choice prompt.
## Unlike the other overlays this has no .tscn — the button list is built
## dynamically because option counts and labels are determined at runtime.
##
## Two layout modes:
##   - desktop: buttons are added INSIDE `action_panel`, the host hides the
##     action-button rows and shows just the choice buttons in their place.
##   - mobile: buttons are wrapped in a PanelContainer anchored to the
##     bottom-right of the host scene.
##
## Public API:
##   open(host: Control, action_panel: Control, options, prompt, mobile, on_select)
##   close()
##
## `on_select` is invoked as `Callable(index: int)` when the user picks.
## `close()` is the host's responsibility once the choice is resolved.

const _BUTTON_MIN_WIDTH := 325
const _BUTTON_MOBILE_HEIGHT := 60

var _container: VBoxContainer = null
var _panel: PanelContainer = null  # only used on mobile
var _on_select: Callable = Callable()
var _is_open: bool = false


func is_open() -> bool:
	return _is_open


func open(
	host: Control,
	action_panel: Control,
	options: Array,
	mobile: bool,
	on_select: Callable,
) -> void:
	_on_select = on_select
	_container = VBoxContainer.new()
	_container.name = "ChoiceContainer"

	if mobile:
		# Anchor a panel above the bottom action bar on the right side.
		_panel = PanelContainer.new()
		_panel.anchor_left = 1.0
		_panel.anchor_right = 1.0
		_panel.anchor_top = 1.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = -350.0
		_panel.offset_right = -6.0
		_panel.offset_top = -130.0 - options.size() * 50.0
		_panel.offset_bottom = -130.0
		_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_panel.z_index = 56
		_panel.add_child(_container)
		host.add_child(_panel)
	else:
		action_panel.add_child(_container)

	for i in range(options.size()):
		var btn := Button.new()
		btn.text = options[i]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size.x = _BUTTON_MIN_WIDTH
		btn.custom_minimum_size.y = _BUTTON_MOBILE_HEIGHT if mobile else 0
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL if mobile else Control.SIZE_SHRINK_END
		if mobile:
			btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.pressed.connect(_on_button_pressed.bind(i))
		_container.add_child(btn)

	_is_open = true


func close() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
	if _container:
		# When desktop layout is in use the container is a direct child of
		# action_panel and has no wrapper. queue_free either way.
		if _container.get_parent():
			_container.queue_free()
		_container = null
	_is_open = false


func _on_button_pressed(index: int) -> void:
	if _on_select.is_valid():
		_on_select.call(index)
