class_name BoardEditorOverlayUI
extends Control

## F4 debug board editor (debug builds, local SOLO / SOLO_BOT games only).
## Left side panel: searchable pool of every card template with click-to-place
## onto zones / strategy slots / hands / decks / discards / monster stacks of
## either player, an inspector for per-card stack surgery (reorder / remove /
## reroute, incl. deck reorder), rage / monster-zone / turn-flag widgets, and
## snapshot save / load / flow-patch via GameSerializer.
##
## Free-form by design — no rules validation (see scripts/tools/board_editor.gd).
## Debug-grade UI: mouse-first, untranslated strings, imperative layout.

const CARD_SCENE: PackedScene = preload("res://scenes/cards/Card.tscn")
const CARD_SIZE := Vector2(120, 168)
const POOL_RESULT_CAP := 60
const POOL_COLUMNS := 3
const SCROLLBAR_RESERVE := 14.0

var _editor: BoardEditor
var _board: GameBoard

# UI
var _search_edit: LineEdit
var _search_timer: Timer
var _type_buttons: Dictionary = {}  # type(int, -1 = all) -> Button
var _pool_scroll: ScrollContainer
var _pool_grid: GridContainer
var _pool_count: Label
var _rage_value: Label
var _zone_value: Label
var _flag_invaded: CheckBox
var _flag_played: CheckBox
var _hand_strip: HBoxContainer
var _status: Label
var _inspector_box: VBoxContainer
var _inspector_title: Label
var _inspector_rows: VBoxContainer
var _pid_buttons: Array[Button] = []
var _bot_refresh_timer: Timer

# State
var _panel_pid: int = 0
var _type_filter: int = -1
var _criteria: Array = []
var _placing: Dictionary = {}  # template dict while in placing mode
var _placed_count: int = 0
var _pick_stack: bool = false  # inspect-next-board-click mode
var _inspecting: Dictionary = {}  # container descriptor while inspector shown
var _signals_hooked: bool = false


static func can_edit(is_debug: bool, is_multiplayer: bool, has_turn_manager: bool) -> bool:
	return is_debug and not is_multiplayer and has_turn_manager


## Placement choices offered when a board target of `kind` is clicked while
## placing a card of `card_type`. Kinds: zone, monster_zone (the zone the
## target player's monster occupies — cards land in the monster's own
## stack, never the covered zone array), strategy, deck, discard,
## monster_deck. Each entry: {op, label}.
static func placement_options(card_type: int, kind: String) -> Array:
	match kind:
		"zone":
			var opts := []
			if card_type == CardEnums.CardType.MONSTER:
				opts.append({"op": "monster_set_stack", "label": "Set current (old → stack below)"})
				opts.append({"op": "monster_set_discard", "label": "Set current (old → discard)"})
				opts.append({"op": "monster_stack_below", "label": "Stack directly below current"})
				opts.append({"op": "monster_stack_bottom", "label": "Stack at bottom"})
			opts.append({"op": "zone_top", "label": "Zone stack (top)"})
			opts.append({"op": "zone_under", "label": "Zone stack (under)"})
			return opts
		"monster_zone":
			if card_type == CardEnums.CardType.MONSTER:
				return [
					{"op": "monster_set_stack", "label": "Set current (old → stack below)"},
					{"op": "monster_set_discard", "label": "Set current (old → discard)"},
					{"op": "monster_stack_below", "label": "Stack directly below current"},
					{"op": "monster_stack_bottom", "label": "Stack at bottom"},
				]
			return [
				{"op": "monster_under_top", "label": "Under monster (top of stack)"},
				{"op": "monster_under_bottom", "label": "Under monster (bottom of stack)"},
			]
		"strategy":
			return [
				{"op": "strategy_set", "label": "Set strategy (evict → discard)"},
				{"op": "strategy_under_top", "label": "Stack under (top)"},
				{"op": "strategy_under_bottom", "label": "Stack under (bottom)"},
			]
		"deck":
			return [
				{"op": "deck_top", "label": "Deck (top)"},
				{"op": "deck_bottom", "label": "Deck (bottom)"},
			]
		"discard":
			return [{"op": "discard", "label": "Discard pile"}]
		"monster_deck":
			return [{"op": "monster_deck", "label": "Monster deck"}]
	return []


## Slot only emits slot_clicked when it holds a card or is in selection mode
## (slot.gd _on_gui_input) — arm slots while placing / stack-picking so
## EMPTY zones and strategy slots accept the drop click, the same mechanism
## the SelectionController uses for zone-target prompts.
static func arm_slots(slots: Array, on: bool) -> void:
	for slot in slots:
		if slot != null:
			slot.in_selection_mode = on


func _ready() -> void:
	visible = false
	_board = get_parent() as GameBoard
	_build_ui()
	GamepadHelper.register_modal(self, _pad_focus_provider)


func _pad_focus_provider() -> Control:
	return GamepadHelper.find_first_focusable(self)


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F4:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		_close()
		return
	if _board == null or not can_edit(
			OS.is_debug_build(), _board.is_multiplayer_game, _board.turn_manager != null):
		return
	if _editor == null:
		_editor = BoardEditor.new(_board.turn_manager)
		# deck_clicked has no default board handler — route it ourselves.
		# (Deferred to first open: the board's @onready refs don't exist yet
		# when this overlay's _ready runs, children ready before the parent.)
		_board.player1_board.deck_clicked.connect(_on_deck_area_clicked)
		_board.player2_board.deck_clicked.connect(_on_deck_area_clicked)
	_hook_state_signals()
	visible = true
	_show_pool_page()
	_refresh_pool()
	_refresh_values()
	_set_status("F4/ESC closes. Click a pool card to place it.")


func _close() -> void:
	_stop_placing()
	_close_inspector()
	visible = false


## ESC ladder hook: returns true when the event was consumed.
func handle_cancel() -> bool:
	if not visible:
		return false
	if not _placing.is_empty():
		_stop_placing()
		return true
	if not _inspecting.is_empty():
		_close_inspector()
		_show_pool_page()
		return true
	_close()
	return true


# ------------------------------------------------------------------
# UI construction
# ------------------------------------------------------------------

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Header: title + player toggle + close
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "BOARD EDITOR"
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for pid in range(2):
		var pbtn := Button.new()
		pbtn.text = "P%d" % (pid + 1)
		pbtn.toggle_mode = true
		pbtn.button_pressed = pid == _panel_pid
		pbtn.pressed.connect(_on_pid_toggled.bind(pid))
		header.add_child(pbtn)
		_pid_buttons.append(pbtn)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	# Search
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search (name, cp>2000, r=3, !text)"
	_search_edit.text_changed.connect(_on_search_changed)
	vbox.add_child(_search_edit)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.25
	_search_timer.timeout.connect(_on_search_debounce)
	add_child(_search_timer)

	# Type filter
	var filter_row := HBoxContainer.new()
	vbox.add_child(filter_row)
	for entry in [[-1, "All"], [CardEnums.CardType.MONSTER, "Mon"],
			[CardEnums.CardType.BATTLE, "Btl"], [CardEnums.CardType.STRATEGY, "Str"]]:
		var fbtn := Button.new()
		fbtn.text = entry[1]
		fbtn.toggle_mode = true
		fbtn.button_pressed = entry[0] == _type_filter
		fbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fbtn.pressed.connect(_on_type_filter.bind(entry[0]))
		filter_row.add_child(fbtn)
		_type_buttons[entry[0]] = fbtn

	# Pool
	_pool_scroll = ScrollContainer.new()
	_pool_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pool_scroll.follow_focus = true
	_pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pool_scroll.resized.connect(_apply_pool_card_sizes)
	vbox.add_child(_pool_scroll)
	_pool_grid = GridContainer.new()
	_pool_grid.columns = POOL_COLUMNS
	_pool_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pool_scroll.add_child(_pool_grid)
	_pool_count = Label.new()
	_pool_count.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_pool_count)

	# Inspector (swapped in for the pool)
	_inspector_box = VBoxContainer.new()
	_inspector_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_box.visible = false
	vbox.add_child(_inspector_box)
	var insp_header := HBoxContainer.new()
	_inspector_box.add_child(insp_header)
	var back := Button.new()
	back.text = "← Pool"
	back.pressed.connect(func() -> void:
		_close_inspector()
		_show_pool_page())
	insp_header.add_child(back)
	_inspector_title = Label.new()
	_inspector_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_title.clip_text = true
	insp_header.add_child(_inspector_title)
	var insp_scroll := ScrollContainer.new()
	insp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_box.add_child(insp_scroll)
	_inspector_rows = VBoxContainer.new()
	_inspector_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	insp_scroll.add_child(_inspector_rows)

	# While placing: hand targets have no board click area.
	_hand_strip = HBoxContainer.new()
	_hand_strip.visible = false
	vbox.add_child(_hand_strip)
	for pid in range(2):
		var hbtn := Button.new()
		hbtn.text = "→ P%d hand" % (pid + 1)
		hbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbtn.pressed.connect(_on_hand_target.bind(pid))
		_hand_strip.add_child(hbtn)

	# Counters / flags
	var rage_row := HBoxContainer.new()
	vbox.add_child(rage_row)
	_rage_value = _spinner_row(rage_row, "Rage", func(delta: int) -> void:
		if _commit_ok():
			_editor.adjust_rage(_panel_pid, delta)
			_after_edit("rage %+d" % delta))
	_zone_value = _spinner_row(rage_row, "Zone", func(delta: int) -> void:
		if _commit_ok():
			await _editor.set_monster_zone(_panel_pid, _panel_player().monster_zone + delta)
			_after_edit("monster zone %+d" % delta))

	var flag_row := HBoxContainer.new()
	vbox.add_child(flag_row)
	_flag_invaded = CheckBox.new()
	_flag_invaded.text = "Invaded"
	_flag_invaded.toggled.connect(func(v: bool) -> void:
		if _commit_ok():
			_editor.set_turn_flag(_panel_pid, "has_invaded_this_turn", v)
			_after_edit("invaded=%s" % v))
	flag_row.add_child(_flag_invaded)
	_flag_played = CheckBox.new()
	_flag_played.text = "Played monster"
	_flag_played.toggled.connect(func(v: bool) -> void:
		if _commit_ok():
			_editor.set_turn_flag(_panel_pid, "has_played_monster_this_turn", v)
			_after_edit("played_monster=%s" % v))
	flag_row.add_child(_flag_played)

	# Inspect shortcuts (panel player) + pick-a-stack mode
	var insp_row := HBoxContainer.new()
	vbox.add_child(insp_row)
	for entry in [["Deck", "deck"], ["Disc", "discard"], ["Mon", "monster"], ["Hand", "hand"]]:
		var ibtn := Button.new()
		ibtn.text = entry[0]
		ibtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ibtn.pressed.connect(_on_inspect_shortcut.bind(entry[1]))
		insp_row.add_child(ibtn)
	var pick := Button.new()
	pick.text = "🔍 Stack"
	pick.tooltip_text = "Then click a zone / strategy slot to edit its stack"
	pick.pressed.connect(func() -> void:
		_stop_placing()
		_pick_stack = true
		_highlight_targets(true)
		_set_status("Click a zone or strategy slot to inspect its stack."))
	insp_row.add_child(pick)

	# Snapshots
	var snap_row := HBoxContainer.new()
	vbox.add_child(snap_row)
	for entry in [["Save", _on_save_pressed], ["Load", _on_load_pressed], ["Turn…", _on_turn_pressed]]:
		var sbtn := Button.new()
		sbtn.text = entry[0]
		sbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sbtn.pressed.connect(entry[1])
		snap_row.add_child(sbtn)

	# Status
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 34)
	_status.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_status)


func _spinner_row(parent: Control, label_text: String, on_delta: Callable) -> Label:
	var lbl := Label.new()
	lbl.text = label_text
	parent.add_child(lbl)
	var minus := Button.new()
	minus.text = "−"
	minus.pressed.connect(func() -> void: on_delta.call(-1))
	parent.add_child(minus)
	var value := Label.new()
	value.text = "0"
	value.custom_minimum_size = Vector2(24, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(value)
	var plus := Button.new()
	plus.text = "+"
	plus.pressed.connect(func() -> void: on_delta.call(1))
	parent.add_child(plus)
	return value


# ------------------------------------------------------------------
# Pool
# ------------------------------------------------------------------

func _show_pool_page() -> void:
	_inspector_box.visible = false
	_pool_scroll.visible = true
	_pool_count.visible = true


func _on_search_changed(_text: String) -> void:
	_search_timer.start()


func _on_search_debounce() -> void:
	_criteria = CardSearch.parse(_search_edit.text)
	_refresh_pool()


func _on_type_filter(type: int) -> void:
	_type_filter = type
	for key in _type_buttons:
		_type_buttons[key].set_pressed_no_signal(key == type)
	_refresh_pool()


func _on_pid_toggled(pid: int) -> void:
	_panel_pid = pid
	for i in range(_pid_buttons.size()):
		_pid_buttons[i].set_pressed_no_signal(i == pid)
	_refresh_values()


func _pool_templates() -> Array:
	var out: Array = []
	for card_id in CardData.CARD_TEMPLATES:
		var card: Dictionary = CardData.CARD_TEMPLATES[card_id]
		if card.get("card_type") == CardEnums.CardType.RAGE:
			continue
		if _type_filter >= 0 and card.get("card_type", -1) != _type_filter:
			continue
		if not CardSearch.matches(card, _criteria):
			continue
		out.append(card)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("id", "") < b.get("id", ""))
	return out


## Card cell sized to fit POOL_COLUMNS across the scroll width (aspect
## preserved) so the grid never scrolls horizontally. Falls back to
## CARD_SIZE before the first layout pass.
func _pool_cell_size() -> Vector2:
	var h_sep: int = _pool_grid.get_theme_constant("h_separation")
	var avail: float = _pool_scroll.size.x - SCROLLBAR_RESERVE - h_sep * (POOL_COLUMNS - 1)
	var w: float = floorf(avail / POOL_COLUMNS)
	if w < 40.0:
		return CARD_SIZE
	return Vector2(w, floorf(w * CARD_SIZE.y / CARD_SIZE.x))


## Re-fit existing pool cards on panel resize (no rebuild).
func _apply_pool_card_sizes() -> void:
	var cell := _pool_cell_size()
	for card in OverlayGridUtil.grid_cards(_pool_grid):
		card.custom_minimum_size = cell
		card.size = cell


func _refresh_pool() -> void:
	OverlayGridUtil.clear_grid(_pool_grid, _on_pool_card_clicked)
	var templates := _pool_templates()
	var shown: int = mini(templates.size(), POOL_RESULT_CAP)
	var router: EffectUIRouter = BoardModule.find_router(self)
	var zoom: Callable = router.card_zoom_request if router else Callable()
	var cell := _pool_cell_size()
	for i in range(shown):
		var card_data: Dictionary = templates[i]
		var card: Control = CARD_SCENE.instantiate()
		card.skip_effect_load = true
		card.set_card_data_dict(card_data)
		card.custom_minimum_size = cell
		card.size = cell
		card.drag_enabled = false
		card.click_on_release = true
		card.is_selectable = true
		card.card_clicked.connect(_on_pool_card_clicked)
		# Contained hover (subtle scale, no lift — the default raise blows
		# out of the grid cell) + right-click / double-click zoom.
		OverlayGridUtil.set_gallery_hover(card, zoom)
		GamepadHelper.make_pad_focusable(card)
		card.set_meta(OverlayGridUtil.GRID_CARD_META, true)
		_pool_grid.add_child(card)
	if templates.size() > shown:
		_pool_count.text = "Showing %d of %d — refine the search" % [shown, templates.size()]
	else:
		_pool_count.text = "%d cards" % templates.size()


# ------------------------------------------------------------------
# Placement
# ------------------------------------------------------------------

func _on_pool_card_clicked(card: Control) -> void:
	var card_data: Dictionary = card.card_data if "card_data" in card else {}
	if card_data.is_empty():
		return
	if not _placing.is_empty() and _placing.get("id", "") == card_data.get("id", ""):
		_stop_placing()
		return
	_begin_placing(card_data)


func _begin_placing(template: Dictionary) -> void:
	if not _edits_allowed():
		return
	_pick_stack = false
	_placing = template
	_placed_count = 0
	_hand_strip.visible = true
	_highlight_targets(true)
	_set_status("Placing %s — click a zone / strategy / deck / discard target (ESC cancels)."
			% template.get("name", template.get("id", "?")))


func _stop_placing() -> void:
	if _placing.is_empty() and not _pick_stack:
		return
	_placing = {}
	_pick_stack = false
	_hand_strip.visible = false
	_highlight_targets(false)
	_set_status("")


func _highlight_targets(on: bool) -> void:
	if _board == null:
		return
	var all_zones: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	for pboard in [_board.player1_board, _board.player2_board]:
		if on:
			pboard.highlight_valid_zones(all_zones)
			pboard.highlight_strategy_zones()
			pboard.highlight_discard_zone(true)
		else:
			pboard.clear_highlights()
		arm_slots(pboard.zone_slots, on)
		# The board renders 3 strategy slots; the engine has 2 zones — arm
		# only the real ones (the engine also bounds-guards slot indices).
		arm_slots(pboard.strategy_slots.slice(0, 2), on)


## True when `index` is the zone the player's monster currently occupies —
## clicks there address the monster's own stack, not the covered zone array.
func _is_monster_zone(pid: int, index: int) -> bool:
	if _board == null or _board.turn_manager == null:
		return false
	var player: PlayerState = _board.turn_manager.game_state.players[pid]
	return not player.current_monster.is_empty() and index == player.monster_zone - 1


## GameBoard click-handler hook. Returns true when the click was consumed
## (placing drop or stack-pick). index is 0-based (zone/strategy) or -1.
func intercept_board_click(kind: String, pid: int, index: int) -> bool:
	if not visible:
		return false
	if kind == "zone" and _is_monster_zone(pid, index):
		kind = "monster_zone"
	if _pick_stack:
		_pick_stack = false
		_highlight_targets(false)
		match kind:
			"zone":
				_open_inspector({"pid": pid, "container": "zone", "zone": index})
			"monster_zone":
				_open_inspector({"pid": pid, "container": "monster"})
			"strategy":
				_open_inspector({"pid": pid, "container": "strategy", "slot": index})
			"discard":
				_open_inspector({"pid": pid, "container": "discard"})
			"deck":
				_open_inspector({"pid": pid, "container": "deck"})
			"monster_deck":
				_open_inspector({"pid": pid, "container": "monster_deck"})
		return true
	if _placing.is_empty():
		return false
	if not _edits_allowed():
		_set_status("An effect prompt is in flight — resolve it first.")
		return true
	var options := placement_options(_placing.get("card_type", -1), kind)
	if options.is_empty():
		return true
	if options.size() == 1:
		_drop_card(options[0]["op"], pid, index)
		return true
	var menu := PopupMenu.new()
	for i in range(options.size()):
		menu.add_item(options[i]["label"], i)
	menu.id_pressed.connect(func(id: int) -> void:
		_drop_card(options[id]["op"], pid, index))
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))
	return true


func _on_deck_area_clicked(pid: int) -> void:
	intercept_board_click("deck", pid, -1)


func _on_hand_target(pid: int) -> void:
	if _placing.is_empty() or not _edits_allowed():
		return
	_drop_card("hand", pid, -1)


func _drop_card(op: String, pid: int, index: int) -> void:
	var card: Dictionary = _editor.mint_card(_placing.get("id", ""))
	if card.is_empty():
		return
	await apply_placement(op, pid, index, card)
	_placed_count += 1
	_set_status("Placed %s ×%d — keep clicking targets, ESC to stop."
			% [_placing.get("name", "?"), _placed_count])
	_after_edit("place %s" % card.get("id", ""))


## Execute one placement op through the mutation engine. Split from the
## click flow so tests can drive it with a prepared card. Coroutine: the
## monster "Set current" ops also move the monster to the clicked zone,
## which resolves the crush rule through the engine.
func apply_placement(op: String, pid: int, index: int, card: Dictionary) -> void:
	match op:
		"zone_top":
			_editor.add_to_zone(pid, index, card, true)
		"zone_under":
			_editor.add_to_zone(pid, index, card, false)
		"strategy_set":
			for evicted in _editor.set_strategy(pid, index, card):
				_editor.add_to_discard(pid, evicted)
		"strategy_under_top":
			_editor.add_under_strategy(pid, index, card, true)
		"strategy_under_bottom":
			_editor.add_under_strategy(pid, index, card, false)
		"monster_set_stack":
			_editor.set_current_monster(pid, card, "stack_top")
			if index >= 0:
				await _editor.set_monster_zone(pid, index + 1)
		"monster_set_discard":
			_editor.set_current_monster(pid, card, "discard")
			if index >= 0:
				await _editor.set_monster_zone(pid, index + 1)
		"monster_stack_below", "monster_under_top":
			_editor.stack_under_monster(pid, card, 0)
		"monster_stack_bottom", "monster_under_bottom":
			_editor.stack_under_monster(pid, card, -1)
		"deck_top":
			_editor.add_to_deck(pid, card, 0)
		"deck_bottom":
			_editor.add_to_deck(pid, card, -1)
		"discard":
			_editor.add_to_discard(pid, card)
		"monster_deck":
			_editor.add_to_monster_deck(pid, card)
		"hand":
			_editor.add_to_hand(pid, card)


# ------------------------------------------------------------------
# Inspector
# ------------------------------------------------------------------

func _on_inspect_shortcut(container: String) -> void:
	_stop_placing()
	_open_inspector({"pid": _panel_pid, "container": container})


func _open_inspector(desc: Dictionary) -> void:
	_inspecting = desc
	_pool_scroll.visible = false
	_pool_count.visible = false
	_inspector_box.visible = true
	_refresh_inspector()


func _close_inspector() -> void:
	_inspecting = {}
	_inspector_box.visible = false


func _inspector_container_cards() -> Array:
	var player: PlayerState = _board.turn_manager.game_state.players[_inspecting.get("pid", 0)]
	match str(_inspecting.get("container", "")):
		"zone":
			return player.zones[_inspecting.get("zone", 0)]
		"strategy":
			var rows: Array = []
			var strat: Dictionary = player.strategy_zones[_inspecting.get("slot", 0)]
			if not strat.is_empty():
				rows.append(strat)
			rows.append_array(player.strategy_zone_stacks[_inspecting.get("slot", 0)])
			return rows
		"monster":
			var rows: Array = []
			if not player.current_monster.is_empty():
				rows.append(player.current_monster)
			rows.append_array(player.monster_stack)
			return rows
		"hand":
			return player.hand
		"deck":
			return player.main_deck
		"discard":
			return player.discard_pile
		"monster_deck":
			return player.monster_deck
	return []


func _refresh_inspector() -> void:
	for child in _inspector_rows.get_children():
		child.queue_free()
	if _inspecting.is_empty():
		return
	var pid: int = _inspecting.get("pid", 0)
	var container: String = str(_inspecting.get("container", ""))
	var cards := _inspector_container_cards()
	var where: String = container
	if container == "zone":
		where = "zone %d" % (_inspecting.get("zone", 0) + 1)
	elif container == "strategy":
		where = "strategy %d" % (_inspecting.get("slot", 0) + 1)
	_inspector_title.text = " P%d %s (%d) — top first" % [pid + 1, where, cards.size()]
	for i in range(cards.size()):
		_inspector_rows.add_child(_make_inspector_row(pid, container, i, cards[i], cards.size()))


func _make_inspector_row(pid: int, container: String, i: int, card: Dictionary, total: int) -> Control:
	var row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = str(card.get("name", card.get("id", "?")))
	name_lbl.clip_text = true
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.tooltip_text = str(card.get("id", ""))
	row.add_child(name_lbl)

	# Container-specific row semantics: in "strategy"/"monster" views row 0
	# is the strategy card / current monster; later rows are the under-stack
	# (stack index = i - 1).
	var head_row: bool = (container == "strategy" or container == "monster") and i == 0
	var stack_index: int = i - 1 if (container == "strategy" or container == "monster") else i
	var src := _row_source(pid, container, head_row, stack_index)

	if container == "monster" and not head_row:
		_row_btn(row, "★", "Make current (old → stack)", func() -> void:
			if _commit_ok():
				_editor.promote_from_stack(pid, stack_index, "stack_top")
				_after_edit("promote monster")
				_refresh_inspector())
	if container in ["zone", "deck", "monster_stack"] or (container == "monster" and not head_row) \
			or (container == "strategy" and not head_row):
		_row_btn(row, "↑", "Move up", _reorder_action(pid, container, head_row, stack_index, -1))
		_row_btn(row, "↓", "Move down", _reorder_action(pid, container, head_row, stack_index, 1))
	if container != "hand":
		_row_btn(row, "→H", "To hand", func() -> void:
			if _commit_ok():
				_editor.move_card(src, {"pid": pid, "container": "hand"})
				_after_edit("to hand")
				_refresh_inspector())
	if container != "discard":
		_row_btn(row, "→D", "To discard", func() -> void:
			if _commit_ok():
				_editor.move_card(src, {"pid": pid, "container": "discard"})
				_after_edit("to discard")
				_refresh_inspector())
	_row_btn(row, "✕", "Remove from game", func() -> void:
		if _commit_ok():
			_remove_row(src)
			_after_edit("remove")
			_refresh_inspector())
	return row


func _row_source(pid: int, container: String, head_row: bool, stack_index: int) -> Dictionary:
	match container:
		"zone":
			return {"pid": pid, "container": "zone", "zone": _inspecting.get("zone", 0), "index": stack_index}
		"strategy":
			if head_row:
				return {"pid": pid, "container": "strategy", "slot": _inspecting.get("slot", 0)}
			return {"pid": pid, "container": "strategy_under", "slot": _inspecting.get("slot", 0), "index": stack_index}
		"monster":
			if head_row:
				return {"pid": pid, "container": "monster"}
			return {"pid": pid, "container": "monster_stack", "index": stack_index}
	return {"pid": pid, "container": container, "index": stack_index}


func _remove_row(src: Dictionary) -> void:
	# Remove without a destination — the mover's remove primitives already
	# emit the right signals.
	_editor._remove_desc(src)


func _reorder_action(pid: int, container: String, head_row: bool, index: int, delta: int) -> Callable:
	return func() -> void:
		if not _commit_ok():
			return
		match container:
			"zone":
				_editor.move_zone_card(pid, _inspecting.get("zone", 0), index, index + delta)
			"deck":
				if index + delta >= 0:
					var card := _editor.remove_from_deck(pid, index)
					if not card.is_empty():
						_editor.add_to_deck(pid, card, index + delta)
			"strategy":
				if not head_row and index + delta >= 0:
					var s_card := _editor.remove_under_strategy(pid, _inspecting.get("slot", 0), index)
					if not s_card.is_empty():
						var slot: int = _inspecting.get("slot", 0)
						var stack: Array = _board.turn_manager.game_state.players[pid].strategy_zone_stacks[slot]
						stack.insert(clampi(index + delta, 0, stack.size()), s_card)
						_board.turn_manager.game_state.players[pid].strategy_zones_changed.emit()
			"monster", "monster_stack":
				if index + delta >= 0:
					var m_card := _editor.remove_from_monster_stack(pid, index)
					if not m_card.is_empty():
						_editor.stack_under_monster(pid, m_card, index + delta)
		_after_edit("reorder")
		_refresh_inspector()


# ------------------------------------------------------------------
# Values / status / safety
# ------------------------------------------------------------------

func _panel_player() -> PlayerState:
	return _board.turn_manager.game_state.players[_panel_pid]


func _hook_state_signals() -> void:
	if _signals_hooked or _board == null or _board.turn_manager == null:
		return
	_signals_hooked = true
	for player in _board.turn_manager.game_state.players:
		player.rage_changed.connect(func(_v: int) -> void: _refresh_values())
		player.monster_changed.connect(_refresh_values)


func _refresh_values() -> void:
	if not visible or _board == null or _board.turn_manager == null:
		return
	var player := _panel_player()
	_rage_value.text = str(player.rage)
	_zone_value.text = str(player.monster_zone)
	_flag_invaded.set_pressed_no_signal(player.has_invaded_this_turn)
	_flag_played.set_pressed_no_signal(player.has_played_monster_this_turn)


func _set_status(text: String) -> void:
	_status.text = text


func _prompt_active() -> bool:
	if _board == null:
		return false
	return _board.waiting_for_card_select or _board.waiting_for_zone_select \
			or _board._zone_target_selecting or _board._zones_target_selecting \
			or _board._discard_selecting or _board._choice_selecting


func _edits_allowed() -> bool:
	return not _prompt_active()


func _commit_ok() -> bool:
	if _editor == null:
		return false
	if not _edits_allowed():
		_set_status("An effect prompt is in flight — resolve it first.")
		return false
	return true


func _after_edit(what: String) -> void:
	if _status.text.is_empty() or _placing.is_empty():
		_set_status("Edited: %s" % what)
	_refresh_values()
	_schedule_bot_refresh()


## Bot games: injected/removed cards invalidate the bot's deck analysis and
## any in-flight combo/planner state. Debounced; skipped while the bot is
## mid-decision (retried on the next edit).
func _schedule_bot_refresh() -> void:
	if _board == null or not _board.is_bot_game:
		return
	if _bot_refresh_timer == null:
		_bot_refresh_timer = Timer.new()
		_bot_refresh_timer.one_shot = true
		_bot_refresh_timer.wait_time = 0.5
		_bot_refresh_timer.timeout.connect(_do_bot_refresh)
		add_child(_bot_refresh_timer)
	_bot_refresh_timer.start()


func _do_bot_refresh() -> void:
	var session: GameSession = BoardModule.find_session(self)
	if session == null or session.turn_manager == null:
		return
	if session.game_state.current_player_id == 1:
		return  # bot mid-turn — refreshing now could yank state under it
	session.refresh_bot_analysis()


# ------------------------------------------------------------------
# Snapshots
# ------------------------------------------------------------------

func _serialize_current() -> Dictionary:
	var mode_str: String = "solo_bot" if NetworkManager.mode == NetworkManager.Mode.SOLO_BOT else "solo"
	var diff_str: String = BotConfig.Difficulty.keys()[NetworkManager.bot_difficulty] if _board.is_bot_game else ""
	var d_names: Array[String] = [
		DecklistManager.get_player_deck_name(0),
		DecklistManager.get_player_deck_name(1),
	]
	var data := GameSerializer.serialize_game_state(
			_board.turn_manager.game_state, _board._first_player_id, mode_str,
			diff_str, d_names, randi(), _board.turn_manager.effect_handler)
	data["editor_snapshot"] = true
	return data


func _on_save_pressed() -> void:
	if _board == null or _board.turn_manager == null:
		return
	var path := GameSerializer.save_game_to_file(_serialize_current())
	_set_status("Saved snapshot: %s" % path.get_file() if not path.is_empty() else "Save failed.")


func _on_load_pressed() -> void:
	var saves := GameSerializer.list_saves()
	if saves.is_empty():
		_set_status("No saves found.")
		return
	var menu := PopupMenu.new()
	var count: int = mini(saves.size(), 15)
	for i in range(count):
		var entry: Dictionary = saves[i]
		var tag: String = "★ " if entry.get("is_favorite", false) else ""
		menu.add_item("%s%s — turn %s" % [tag, entry.get("timestamp", "?"), entry.get("turn_number", "?")], i)
	menu.id_pressed.connect(func(id: int) -> void:
		_load_snapshot(str(saves[id]["path"])))
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


func _load_snapshot(path: String) -> void:
	var data := GameSerializer.load_save_file(path)
	if data.is_empty():
		_set_status("Failed to load %s" % path.get_file())
		return
	GameSerializer.pending_load = data
	get_tree().reload_current_scene()


func _on_turn_pressed() -> void:
	if _board == null or _board.turn_manager == null:
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Set turn / phase (reloads match)"
	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)
	var gs: GameState = _board.turn_manager.game_state

	var phase_opt := OptionButton.new()
	for key in CardEnums.GamePhase.keys():
		phase_opt.add_item(key)
	phase_opt.select(int(gs.current_phase))
	vbox.add_child(_labeled("Phase", phase_opt))

	var player_opt := OptionButton.new()
	player_opt.add_item("P1")
	player_opt.add_item("P2")
	player_opt.select(gs.current_player_id)
	vbox.add_child(_labeled("Current player", player_opt))

	var turn_spin := SpinBox.new()
	turn_spin.min_value = 1
	turn_spin.max_value = 99
	turn_spin.value = gs.turn_number
	vbox.add_child(_labeled("Turn", turn_spin))

	dialog.confirmed.connect(func() -> void:
		var data := BoardEditor.patch_snapshot(_serialize_current(), {
			"current_phase": phase_opt.selected,
			"current_player_id": player_opt.selected,
			"turn_number": int(turn_spin.value),
		})
		GameSerializer.pending_load = data
		get_tree().reload_current_scene())
	dialog.popup_hide.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(320, 200))


func _labeled(text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(110, 0)
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _row_btn(row: Control, text: String, tip: String, action: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tip
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(action)
	row.add_child(btn)
