class_name EffectStackPanel
extends Node

## Persistent display of the pending standby-effect stack on the right edge
## of the board: every ability waiting to resolve, with the currently
## resolving one marked, so the player stays informed even while the chosen
## effect is mid-resolution (nested prompts included).
##
## Host/solo: fed by GameEvents.effect_stack_changed (and mirrored to the
## remote peer). Multiplayer client: fed by _rpc_effect_stack_changed via
## the board. Dedicated-server clients: fed by EffectUIRouter's broadcast.
##
## Rows are display-only except for hover, which pulses the source card on
## the board via the board's set_card_attention.

const PANEL_WIDTH := 300.0
const ROW_HEIGHT_EST := 44.0

var _board: Node
var _session: GameSession
var _rows: Array = []
var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null


func _ready() -> void:
	_board = get_parent()
	var session_node := _board.get_node_or_null("GameSession")
	if session_node:
		_session = session_node
		_session.session_started.connect(_bind_session)


func _bind_session() -> void:
	if _session.events == null:
		return # Client peer: the stack arrives via MultiplayerSync RPCs
	if not _session.events.effect_stack_changed.is_connected(_on_stack_changed):
		_session.events.effect_stack_changed.connect(_on_stack_changed)


func _on_stack_changed(stack: Array) -> void:
	# P2P host mirrors the stack to the remote peer (the dedicated server
	# mirrors via EffectUIRouter instead — this module doesn't exist there).
	if _board.is_multiplayer_game and NetworkManager.is_host():
		var stack_json := JSON.stringify(stack)
		for peer_id in NetworkManager.peer_player_map:
			if peer_id != multiplayer.get_unique_id():
				RpcLogger.log_send("effect_stack_changed", stack_json.length())
				_board._sync._rpc_effect_stack_changed.rpc_id(peer_id, stack_json)
	show_stack(stack)


func has_rows() -> bool:
	return not _rows.is_empty()


## Clear + hide for a rematch reset.
func reset() -> void:
	_rows = []
	if _panel and is_instance_valid(_panel):
		_panel.visible = false
	_board._selection.clear_stack_hover_preview()


func show_stack(rows: Array) -> void:
	_rows = rows
	# Rebuilding frees any hovered row before its mouse_exited can fire, so
	# drop a lingering attention pulse / hover preview here.
	_board.set_card_attention({}, false)
	_board._selection.clear_stack_hover_preview()
	if rows.is_empty():
		if _panel and is_instance_valid(_panel):
			_panel.visible = false
		_board._update_tracker_collapse()
		return
	_ensure_panel()
	for child in _list.get_children():
		child.queue_free()
	for row in rows:
		if row is Dictionary and not (row as Dictionary).is_empty():
			_list.add_child(_make_row(row))
	_scroll.custom_minimum_size.y = minf(
		rows.size() * ROW_HEIGHT_EST + 4.0,
		_board.get_viewport_rect().size.y * 0.4)
	_panel.visible = true
	_board._update_tracker_collapse()


func _ensure_panel() -> void:
	if _panel and is_instance_valid(_panel):
		return
	_panel = PanelContainer.new()
	_panel.name = "EffectStackDisplay"
	_panel.z_index = 55 # Just below the choice panel (56)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.9)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	# Right edge, below the top bar / mobile phase label; a min-size overflow
	# expands DOWNWARD from the anchor point, which is what we want here.
	var top: float = 100.0 if _board._is_mobile_layout else 52.0
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -6.0 - PANEL_WIDTH
	_panel.offset_right = -6.0
	_panel.offset_top = top
	_panel.offset_bottom = top
	_panel.grow_vertical = Control.GROW_DIRECTION_END

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = tr("STR_GB_EFFECT_STACK_TITLE")
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(title)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 20.0, 0.0)
	vbox.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)

	_board.add_child(_panel)


func _make_row(row: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.add_theme_constant_override("separation", 6)
	var resolving: bool = str(row.get("status", "")) == "resolving"
	var is_opponent: bool = int(row.get("player_id", -1)) != _board.local_player_id

	var base_id: String = str(row.get("base_id", ""))
	if not base_id.is_empty():
		var thumb := OverlayGridUtil.get_choice_thumb(base_id)
		if thumb:
			var icon := TextureRect.new()
			icon.texture = thumb
			icon.custom_minimum_size = Vector2(32, 32)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(icon)

	if is_opponent:
		var tag := Label.new()
		tag.text = tr("STR_GB_STACK_OPPONENT")
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", Color(0.78, 0.6, 1.0))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(tag)

	var label := Label.new()
	var text: String = str(row.get("label", ""))
	label.text = ("▶ " + text) if resolving else text
	label.tooltip_text = tr("STR_GB_STACK_RESOLVING") if resolving else ""
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 13)
	var name_color := Color(0.72, 0.72, 0.8)
	if resolving:
		name_color = Color(1.0, 0.9, 0.3)
	elif is_opponent:
		name_color = Color(0.78, 0.62, 0.95)
	label.add_theme_color_override("font_color", name_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(label)

	var loc = row.get("location", {})
	if loc is Dictionary and not (loc as Dictionary).is_empty():
		hbox.mouse_entered.connect(func() -> void:
			_board.set_card_attention(loc, true)
			_board._selection.show_stack_hover_preview(base_id))
		hbox.mouse_exited.connect(func() -> void:
			_board.set_card_attention(loc, false)
			_board._selection.clear_stack_hover_preview())

	if not is_opponent:
		return hbox
	# Opponent rows sit on a subtle purple tint so ownership reads at a glance.
	var wrapper := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.3, 0.7, 0.22)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	wrapper.add_theme_stylebox_override("panel", style)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(hbox)
	return wrapper
