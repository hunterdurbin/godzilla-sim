class_name GamepadBoardNav
extends Node
## Controller navigation for the game board (presentation-only module).
##
## Cards and slots keep their custom pointer picking and never receive Godot
## focus — this module moves a visual cursor between named board ELEMENTS
## following the explicit up/right/down/left adjacency table in
## BoardCursorMap.MAP (CursorMap resolves it, tie-breaking multi-target
## directions by the last-10-visited history). On pad_confirm it synthesizes
## the exact signals the pointer path emits (CardManager.select_card_at,
## Slot.simulate_click, SelectionController.play_selected_card_to_zone).
## The ACTION_PANEL region hands control to Godot's real focus system so
## ui_accept drives the buttons natively.
##
## SelectionController.selection_context_changed jails the cursor to the
## active prompt's elements: the map's skip-through rule makes invalid
## elements transparent, so movement between valid zones stays spatial.
## Overlays suspend the module (same visibility set as game_board's
## ui_cancel ladder); registered modal dialogs suspend it via the focus
## context stack.
##
## Never loaded by the harness stub or headless server board — no RPC-surface
## impact.

enum Region { NONE, HAND, BOARD, ACTION_PANEL }

const CURSOR_COLOR := Color(0.35, 1.0, 0.55, 0.95)
const CURSOR_PAD := 4.0
const DEFAULT_ELEMENT := "bot_z2"

var _board: Node
var _region: int = Region.NONE
## Current board element id (BoardCursorMap key) while in Region.BOARD.
var _element: String = DEFAULT_ELEMENT
## Card index within the hand while in Region.HAND.
var _hand_index: int = 0
var _map: CursorMap = CursorMap.new(BoardCursorMap.MAP)
var _mode: String = "none"
var _ctx_valid: Array[int] = []
var _ctx_board_pid: int = -1
var _ctx_hand_pid: int = -1
## Prompt jail: element ids the cursor may rest on ({} = free browse).
var _ctx_elements: Dictionary = {}
var _cursor: Panel = null
var _previewing_card: bool = false
## Card under the HAND cursor — survives reorders (sorting rewrites the
## numeric index but the card ref stays valid).
var _cursor_card: Control = null
## Browsing the hand pops it up like the toggle button does; leaving restores
## it — but only when WE expanded it, never clobbering a manual expand.
var _auto_expanded_hand := false


func _ready() -> void:
	_board = get_parent()
	GamepadHelper.gamepad_detected.connect(_on_gamepad_detected)
	GamepadHelper.pointer_detected.connect(_on_pointer_detected)
	GamepadHelper.push_focus_context(_board, _default_focus_control)
	var selection: SelectionController = _board.get_node_or_null("SelectionController")
	if selection:
		selection.selection_context_changed.connect(_on_selection_context_changed)
	# The board's @onready hand refs resolve after this module's _ready
	# (children ready first) — connect once the board has finished.
	_connect_hand_signals.call_deferred()


func _connect_hand_signals() -> void:
	for hand: CardManager in [_board.player1_hand, _board.player2_hand]:
		if hand:
			hand.cards_reordered.connect(_on_hand_reordered.bind(hand))


func _exit_tree() -> void:
	GamepadHelper.pop_focus_context(_board)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_active():
		return
	if event.is_action_pressed("pad_region_next"):
		_cycle_region(1)
	elif event.is_action_pressed("pad_region_prev"):
		_cycle_region(-1)
	elif event.is_action_pressed("pad_end_main"):
		_board._selection.press_primary_button()
	elif event.is_action_pressed("pad_view_discard"):
		_board._on_discard_clicked(_my_pid())
	elif event.is_action_pressed("pad_view_opp_discard"):
		_board._on_discard_clicked(1 - _my_pid())
	elif event.is_action_pressed("pad_menu"):
		if _board._leave_dialog:
			_board._leave_dialog.popup_centered()
	elif event.is_action_pressed("pad_chat"):
		_open_chat()
	elif _region == Region.HAND or _region == Region.BOARD:
		if event.is_action_pressed("pad_nav_left"):
			_move("left")
		elif event.is_action_pressed("pad_nav_right"):
			_move("right")
		elif event.is_action_pressed("pad_nav_up"):
			_move("up")
		elif event.is_action_pressed("pad_nav_down"):
			_move("down")
		elif event.is_action_pressed("pad_confirm"):
			_confirm()
		elif event.is_action_pressed("pad_inspect"):
			_inspect()
		else:
			return
	elif _region == Region.ACTION_PANEL and event.is_action_pressed("pad_nav_down") \
			and _mode == "none" and _panel_focus_at_bottom_edge():
		# Dpad-down past the bottom action row drops into hand browsing.
		_enter_hand()
	else:
		return
	get_viewport().set_input_as_handled()


## Whether the focused action button has no downward focus target inside the
## action panel/FAB — i.e. the mirrored ui_down has nowhere sensible to go,
## so dpad-down should hand over to hand browsing instead.
func _panel_focus_at_bottom_edge() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null:
		return true
	var neighbor := focus_owner.find_valid_focus_neighbor(SIDE_BOTTOM)
	if neighbor == null:
		return true
	var panel: Control = _board.action_panel
	return panel == null or not panel.is_ancestor_of(neighbor)


func _is_active() -> bool:
	if not GamepadHelper.is_using_gamepad():
		return false
	if not GamepadHelper.is_top_context(_board):
		return false
	return not _any_overlay_open()


## Same overlay set (and priority meaning) as the ui_cancel ladder in
## game_board._input — any of these open means the board is not in control.
func _any_overlay_open() -> bool:
	for prop in ["card_zoom_overlay", "deck_arrange_overlay",
			"card_pool_select_overlay", "deck_search_overlay",
			"discard_view_overlay", "monster_deck_view_overlay",
			"zone_stack_view_overlay"]:
		var overlay: CanvasItem = _board.get(prop)
		if overlay and overlay.visible:
			return true
	return false


# --- Device / context transitions ---

func _on_gamepad_detected() -> void:
	if _mode != "none":
		_apply_context()
	else:
		_enter_action_panel()


func _on_pointer_detected() -> void:
	_leave_hand_browse()
	_region = Region.NONE
	_hide_cursor()


func _on_selection_context_changed(ctx: Dictionary) -> void:
	_mode = ctx.get("mode", "none")
	_ctx_valid = ctx.get("valid", [] as Array[int])
	_ctx_board_pid = ctx.get("board_pid", -1)
	_ctx_hand_pid = ctx.get("hand_pid", -1)
	_rebuild_ctx_elements()
	if not GamepadHelper.is_using_gamepad():
		return
	_apply_context()


## Translate the prompt context into the set of map elements the cursor may
## rest on. Empty = free browse (visibility is the only gate).
func _rebuild_ctx_elements() -> void:
	_ctx_elements.clear()
	match _mode:
		"hand_select", "hand_discard":
			_ctx_elements["hand"] = true
		"card_to_zone", "zone_target", "zones_target":
			var side := _side_for_pid(_ctx_board_pid)
			for zone_idx in _ctx_valid:
				_ctx_elements["%s_z%d" % [side, zone_idx + 1]] = true
		"strategy_target":
			var side := _side_for_pid(_ctx_board_pid)
			for strat_idx in _ctx_valid:
				_ctx_elements["%s_strategy_%d" % [side, strat_idx]] = true


func _apply_context() -> void:
	match _mode:
		"hand_select", "hand_discard":
			_enter_hand()
		"card_to_zone", "zone_target", "zones_target", "strategy_target":
			var first := _first_ctx_element()
			if first != "":
				_enter_element(first)
		"choice", "confirm":
			# Real focus takes over (choice buttons / the Confirm button).
			_leave_hand_browse()
			_region = Region.NONE
			_hide_cursor()
			if _mode == "confirm":
				GamepadHelper.refocus()
		_:
			_enter_action_panel()


func _first_ctx_element() -> String:
	# Keep the cursor where it is when it's already on a valid element.
	if _region == Region.BOARD and _ctx_elements.has(_element):
		return _element
	var ids: Array = _ctx_elements.keys()
	ids.sort()
	for id: String in ids:
		if _element_valid(id):
			return id
	return ""


# --- Regions & movement ---

func _cycle_region(dir: int) -> void:
	if _mode != "none":
		return # Prompts jail the cursor
	var order: Array[int] = [Region.ACTION_PANEL, Region.HAND, Region.BOARD]
	var at := order.find(_region)
	var next_region: int = order[(at + dir + order.size()) % order.size()] if at >= 0 else Region.HAND
	match next_region:
		Region.ACTION_PANEL:
			_enter_action_panel()
		Region.HAND:
			_enter_hand()
		Region.BOARD:
			_enter_element(_last_board_element())


## The board element to land on when re-entering the board without a
## direction: the most recently visited valid one, else the default.
func _last_board_element() -> String:
	var hist := _map.visited()
	for i in range(hist.size() - 1, -1, -1):
		if hist[i] != "hand" and _element_valid(hist[i]):
			return hist[i]
	return DEFAULT_ELEMENT if _element_valid(DEFAULT_ELEMENT) else _element


func _move(dir: String) -> void:
	if _region == Region.HAND:
		# Left/right walk the fanned cards; up/down travel the map.
		if dir == "left" or dir == "right":
			_move_hand(-1 if dir == "left" else 1)
			return
		var exit_id := _map.next("hand", dir, _element_valid)
		if exit_id != "":
			_enter_element(exit_id)
		return
	var target := _map.next(_element, dir, _element_valid)
	if target == "" and not _ctx_elements.is_empty() and (dir == "left" or dir == "right"):
		# Prompt jail: a sparse valid set can dead-end the spatial graph
		# (e.g. Z2/Z4/Z6 span both rows). Left/right then cycle the valid
		# elements so every legal target stays reachable.
		target = _ctx_cycle(1 if dir == "right" else -1)
	if target == "":
		return
	if target == "hand":
		_enter_hand()
	else:
		_enter_element(target)


func _ctx_cycle(dir: int) -> String:
	var ids: Array = _ctx_elements.keys().filter(_element_valid)
	ids.sort()
	if ids.is_empty():
		return ""
	var at := ids.find(_element)
	if at < 0:
		return ids[0]
	return ids[(at + dir + ids.size()) % ids.size()]


func _move_hand(dir: int) -> void:
	var valid := _hand_valid_indices()
	if valid.is_empty():
		return
	var at := valid.find(_hand_index)
	_hand_index = valid[(at + dir + valid.size()) % valid.size()] if at >= 0 else valid[0]
	_update_cursor()


func _enter_action_panel() -> void:
	_leave_hand_browse()
	_region = Region.ACTION_PANEL
	_hide_cursor()
	GamepadHelper.refocus()


func _enter_hand() -> void:
	_region = Region.HAND
	_map.push_visited("hand")
	# The module owns input in virtual regions; no control may hold focus or
	# the mirrored ui_* events would double-drive it.
	get_viewport().gui_release_focus()
	if _mode == "none":
		_auto_expand_hand()
	var valid := _hand_valid_indices()
	if valid.is_empty():
		_hide_cursor()
		return
	_hand_index = valid[0] if _hand_index not in valid else _hand_index
	_update_cursor()


func _enter_element(id: String) -> void:
	_clear_preview()
	_leave_hand_browse()
	_region = Region.BOARD
	_element = id
	_map.push_visited(id)
	get_viewport().gui_release_focus()
	_update_cursor()


func _element_valid(id: String) -> bool:
	if not _ctx_elements.is_empty() and not _ctx_elements.has(id):
		return false
	if id == "hand":
		return _hand_mgr() != null
	var control := _resolve_control(id)
	return control != null and control.is_visible_in_tree()


func _hand_valid_indices() -> Array[int]:
	var out: Array[int] = []
	var hand := _hand_mgr()
	if hand == null:
		return out
	if hand.selection_mode and not hand.selectable_indices.is_empty():
		return hand.selectable_indices.duplicate()
	for i in range(hand.managed_cards.size()):
		out.append(i)
	return out


func _auto_expand_hand() -> void:
	if not _board._hand.hand_expanded:
		_board._hand.set_hand_expanded(true)
		_auto_expanded_hand = true


func _leave_hand_browse() -> void:
	if _auto_expanded_hand:
		_auto_expanded_hand = false
		if _board._hand.hand_expanded:
			_board._hand.set_hand_expanded(false)


# --- Element resolution ---

## The physically-bottom playmat is `bot_*`; seat-independent so a future
## board swap keeps the map truthful.
func _board_for_side(side: String) -> Control:
	var p1: Control = _board.player1_board
	var p2: Control = _board.player2_board
	if p1 == null or p2 == null:
		return p1 if side == "bot" else p2
	var p1_bottom: bool = p1.get_global_rect().position.y >= p2.get_global_rect().position.y
	if side == "bot":
		return p1 if p1_bottom else p2
	return p2 if p1_bottom else p1


func _side_for_pid(pid: int) -> String:
	var board := _player_board(pid)
	return "bot" if board == _board_for_side("bot") else "top"


## id -> {kind, control, idx, pid}; {} for hand/unknown ids.
func _resolve(id: String) -> Dictionary:
	var sep := id.find("_")
	if sep <= 0:
		return {}
	var side := id.substr(0, sep)
	var rest := id.substr(sep + 1)
	var board := _board_for_side(side)
	if board == null:
		return {}
	var pid: int = board.player_id
	if rest.begins_with("z"):
		var idx := rest.substr(1).to_int() - 1
		if idx < 0 or idx >= board.zone_slots.size():
			return {}
		return {"kind": "zone", "control": board.zone_slots[idx], "idx": idx, "pid": pid}
	if rest.begins_with("strategy_"):
		var idx := rest.substr(9).to_int()
		if idx < 0 or idx >= board.strategy_slots.size():
			return {}
		return {"kind": "strategy", "control": board.strategy_slots[idx], "idx": idx, "pid": pid}
	match rest:
		"rage":
			return {"kind": "rage", "control": board.rage_display, "idx": 0, "pid": pid}
		"deck":
			return {"kind": "deck", "control": board.deck_display(), "idx": 0, "pid": pid}
		"monster_deck":
			return {"kind": "monster_deck", "control": board.monster_info_display, "idx": 0, "pid": pid}
		"discard":
			return {"kind": "discard", "control": board.discard_display, "idx": 0, "pid": pid}
	return {}


func _resolve_control(id: String) -> Control:
	return _resolve(id).get("control") as Control


# --- Activation ---

func _confirm() -> void:
	if _region == Region.HAND:
		var hand := _hand_mgr()
		if hand and hand.selection_mode:
			hand.select_card_at(_hand_index)
		return
	var entry := _resolve(_element)
	if entry.is_empty():
		return
	# Prompt modes: synthesize the pointer selection path.
	if entry["kind"] == "zone":
		if _mode == "card_to_zone":
			_board._selection.play_selected_card_to_zone(int(entry["idx"]))
			return
		if _mode == "zone_target" or _mode == "zones_target":
			(entry["control"] as Slot).simulate_click()
			_update_cursor() # zones_target keeps selecting after a toggle
			return
	if entry["kind"] == "strategy" and _mode == "strategy_target":
		(entry["control"] as Slot).simulate_click()
		return
	# Free browse = the pointer left-click path per element.
	match entry["kind"]:
		"zone":
			_board._on_zone_slot_clicked(int(entry["idx"]) + 1, int(entry["pid"]))
		"strategy":
			_board._on_strategy_slot_clicked(int(entry["idx"]), int(entry["pid"]))
		"discard":
			_board._on_discard_clicked(int(entry["pid"]))
		"monster_deck":
			_board._on_monster_deck_clicked(int(entry["pid"]))
		_:
			pass # rage/deck: nothing to activate (matches the mouse)


func _inspect() -> void:
	if _region == Region.HAND:
		var card := _hand_card(_hand_index)
		if card and "card_data" in card:
			_board._show_card_zoom(card.card_data)
		return
	var entry := _resolve(_element)
	match entry.get("kind", ""):
		"zone":
			_board._on_zone_slot_right_clicked(int(entry["idx"]) + 1, int(entry["pid"]))
		"strategy":
			_board._on_strategy_slot_right_clicked(int(entry["idx"]), int(entry["pid"]))
		"discard":
			var player: Variant = _board._get_player_state(int(entry["pid"]))
			if player and not player.discard_pile.is_empty():
				_board._show_card_zoom(player.discard_pile.back())


func _open_chat() -> void:
	if _board._is_mobile_layout:
		_board._notify_mobile_log_chat()
	elif _board.chat_input and _board.chat_input.is_visible_in_tree():
		_board.chat_input.grab_focus()


# --- Cursor visual ---

## Sorting/reordering rewrites managed_cards; keep the cursor on the SAME
## card by rebinding the numeric index to the remembered card ref.
func _on_hand_reordered(hand: CardManager) -> void:
	if _region != Region.HAND or hand != _hand_mgr():
		return
	if is_instance_valid(_cursor_card):
		var idx := hand.managed_cards.find(_cursor_card)
		if idx >= 0:
			_hand_index = idx
			_update_cursor()
			return
	# Card left the hand (played/discarded): snap to the first valid index.
	var valid := _hand_valid_indices()
	_hand_index = valid[0] if not valid.is_empty() else 0
	_update_cursor()


func _update_cursor() -> void:
	var target := _cursor_target()
	if target == null:
		_hide_cursor()
		return
	if _cursor == null:
		_cursor = Panel.new()
		_cursor.name = "GamepadCursor"
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = CURSOR_COLOR
		style.set_border_width_all(3)
		style.set_corner_radius_all(6)
		_cursor.add_theme_stylebox_override("panel", style)
		_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cursor.z_index = 100
		_board.add_child(_cursor)
	_cursor_card = target if _region == Region.HAND else null
	var rect := _target_rect(target)
	_cursor.visible = true
	_cursor.global_position = rect.position - Vector2(CURSOR_PAD, CURSOR_PAD)
	_cursor.size = rect.size + Vector2(CURSOR_PAD, CURSOR_PAD) * 2.0
	_refresh_preview()


## Hand cards tween into place over ~0.3s after a reorder — land the cursor
## on the card's arrange TARGET instead of chasing the mid-flight rect.
func _target_rect(target: Control) -> Rect2:
	if _region == Region.HAND:
		var hand := _hand_mgr()
		if hand and hand.card_target_positions.has(target):
			var pos: Vector2 = hand.to_global(hand.card_target_positions[target])
			return Rect2(pos, target.get_global_rect().size)
	return target.get_global_rect()


func _hide_cursor() -> void:
	_clear_preview()
	if _cursor:
		_cursor.visible = false


func _cursor_target() -> Control:
	if _region == Region.HAND:
		return _hand_card(_hand_index)
	if _region == Region.BOARD:
		return _resolve_control(_element)
	return null


## Mirror the pointer hover behavior: the card under the cursor shows in the
## big right-side preview panel (hand cards, and the top card of zone /
## strategy slots and the discard pile).
func _refresh_preview() -> void:
	var data := _cursor_preview_data()
	if data.is_empty():
		_clear_preview()
		return
	_board._show_card_preview(data)
	_previewing_card = true


func _cursor_preview_data() -> Dictionary:
	if _region == Region.HAND:
		var card := _hand_card(_hand_index)
		if card and "card_data" in card:
			return card.card_data
		return {}
	if _region != Region.BOARD:
		return {}
	var entry := _resolve(_element)
	match entry.get("kind", ""):
		"zone", "strategy":
			var held: Control = (entry["control"] as Slot).held_card
			if held and "card_data" in held and not held.is_face_down:
				return held.card_data
		"discard":
			var player: Variant = _board._get_player_state(int(entry["pid"]))
			if player and not player.discard_pile.is_empty():
				return player.discard_pile.back()
	return {}


func _clear_preview() -> void:
	if _previewing_card:
		_board._hide_card_preview()
		_previewing_card = false


# --- Lookups ---

func _my_pid() -> int:
	if _board.is_multiplayer_game:
		return _board.local_player_id
	return _board._get_current_pid()


func _hand_pid() -> int:
	if _mode != "none" and _ctx_hand_pid >= 0:
		return _ctx_hand_pid
	return _my_pid()


func _hand_mgr() -> CardManager:
	return _board.player1_hand if _hand_pid() == 0 else _board.player2_hand


func _hand_card(index: int) -> Control:
	var hand := _hand_mgr()
	if hand == null or index < 0 or index >= hand.managed_cards.size():
		return null
	return hand.managed_cards[index]


func _player_board(pid: int) -> Control:
	return _board.player1_board if pid == 0 else _board.player2_board


## Default focus for the board's focus context (used whenever real focus
## should take over: action panel region, prompt confirm, refocus on device
## switch). Returns null when nothing sensible is enabled.
func _default_focus_control() -> Control:
	var candidates: Array = [
		_board.btn_confirm, _board.btn_end_main, _board.btn_play_battle,
		_board.btn_play_strategy, _board.btn_gain_rage, _board.btn_play_monster,
		_board.btn_invade, _board.btn_cancel,
	]
	if _board._is_mobile_layout:
		var mobile: Node = _board.get_node_or_null("MobileLayout")
		if mobile:
			# Mobile: the pills (confirm/end-main) still lead; the FAB main
			# button is the fallback that opens the action grid.
			candidates.insert(2, mobile.fab_main_button())
	for btn: Variant in candidates:
		var b := btn as Button
		if b and b.is_visible_in_tree() and not b.disabled:
			return b
	return null
