class_name HoverPreview
extends Control

## Drop-in card hover-preview pane. Subscribes to every PlayerBoard
## descendant's `card_preview_requested` / `card_preview_cleared`
## signals — when a player hovers a card, the preview shows a magnified
## version that respects the card's aspect ratio. Strategy cards render
## rotated 90° CCW (matching the in-zone layout).
##
## Drop one into your GameBoard scene; anchor wherever you want the
## preview to appear (top-right works well on desktop). No controller
## wiring needed.
##
## Usage:
##   GameBoard
##   ├── ... layout / seats / hand ...
##   └── HoverPreview                 ← drop me here, anchor top-right

@export var auto_bind: bool = true
## Hide the preview entirely on mobile layouts (which use tap-to-zoom
## via CardZoomOverlay instead).
@export var hide_on_mobile: bool = true

@export_group("Card layout")
## When true (default), the runtime sizes the inner Card to fit this
## Control's rect at `card_aspect_ratio`. When false, the designer sets
## the Card child's anchors directly in the editor — pure WYSIWYG.
@export var auto_layout: bool = true
## Card aspect ratio (width:height). Default 5:7 matches the standard
## Card.tscn proportions. Only used when auto_layout is true.
@export var card_aspect_ratio: Vector2 = Vector2(5, 7)
## Outer padding around the card, in pixels. Only used when
## auto_layout is true.
@export_range(0.0, 32.0, 0.5) var padding: float = 6.0
## Strategy cards render rotated 90° CCW (matches the in-zone landscape
## layout). Set false for boards that don't differentiate strategy
## cards. Only used when auto_layout is true.
@export var rotate_strategy: bool = true
@export_group("")

var _card: Control = null
var _bg: ColorRect = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.8)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	if auto_bind:
		# Defer so PlayerBoard descendants are fully ready (their card
		# data and signal subscriptions are initialized).
		call_deferred("_wire_player_boards")


func _wire_player_boards() -> void:
	var board := find_parent("GameBoard")
	if board == null:
		push_warning("[HoverPreview] No GameBoard ancestor.")
		return
	for pb in board.find_children("*", "PlayerBoard", true, false):
		if not pb.card_preview_requested.is_connected(_on_card_preview_requested):
			pb.card_preview_requested.connect(_on_card_preview_requested)
		if not pb.card_preview_cleared.is_connected(_on_card_preview_cleared):
			pb.card_preview_cleared.connect(_on_card_preview_cleared)


func _on_card_preview_requested(data: Dictionary, play_cost_modifier: int) -> void:
	if hide_on_mobile and GameSettings.use_mobile_layout:
		return
	if data.is_empty():
		return
	if _card == null:
		_card = BoardModule.get_card_scene(self).instantiate()
		if "drag_enabled" in _card:
			_card.drag_enabled = false
		if "hover_scale" in _card:
			_card.hover_scale = 1.0
		if "hover_lift" in _card:
			_card.hover_lift = 0.0
		add_child(_card)
		_set_mouse_filter_ignore_recursive(_card)
	_card.set_card_data_dict(data)
	if _card.has_method("set_play_cost_modifier"):
		_card.set_play_cost_modifier(play_cost_modifier)
	var is_strategy: bool = data.get("card_type", -1) == CardEnums.CardType.STRATEGY
	if auto_layout:
		if is_strategy and rotate_strategy:
			_layout_strategy()
		else:
			_layout_normal()
	if _card.has_method("update_play_cost_badge_layout"):
		_card.update_play_cost_badge_layout()
	visible = true


func _on_card_preview_cleared() -> void:
	visible = false


func _ratio() -> float:
	# Avoid divide-by-zero if designer sets a zero component.
	if card_aspect_ratio.y <= 0.0 or card_aspect_ratio.x <= 0.0:
		return 5.0 / 7.0
	return card_aspect_ratio.x / card_aspect_ratio.y


func _layout_normal() -> void:
	var container_size := size
	var ratio := _ratio()
	var card_w := container_size.x
	var card_h := card_w / ratio
	if card_h > container_size.y:
		card_h = container_size.y
		card_w = card_h * ratio
	var card_pos := Vector2((container_size.x - card_w) / 2.0, (container_size.y - card_h) / 2.0)
	_bg.position = card_pos - Vector2(padding, padding)
	_bg.size = Vector2(card_w, card_h) + Vector2(padding * 2, padding * 2)
	_card.size = Vector2(card_w, card_h)
	_card.position = card_pos
	_card.pivot_offset = Vector2(card_w, card_h) / 2.0
	_card.scale = Vector2.ONE
	_card.rotation = 0.0


func _layout_strategy() -> void:
	var container_size := size
	var ratio := _ratio()
	var visual_h := container_size.y
	var card_w := visual_h
	var card_h := card_w / ratio
	if card_h > container_size.x:
		card_h = container_size.x
		card_w = card_h * ratio
		visual_h = card_w
	var visual_w := card_h
	var card_pos := Vector2(
		container_size.x - visual_w,
		(container_size.y - visual_h) / 2.0
	)
	_card.size = Vector2(card_w, card_h)
	_card.pivot_offset = Vector2(card_w, card_h) / 2.0
	_card.rotation = -PI / 2.0
	_card.scale = Vector2.ONE
	_card.position = card_pos + Vector2((visual_w - card_w) / 2.0, (visual_h - card_h) / 2.0)
	_bg.position = card_pos - Vector2(padding, padding)
	_bg.size = Vector2(visual_w, visual_h) + Vector2(padding * 2, padding * 2)


func _set_mouse_filter_ignore_recursive(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_filter_ignore_recursive(child)
