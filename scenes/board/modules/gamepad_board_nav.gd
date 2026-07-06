class_name GamepadBoardNav
extends Node
## Controller navigation for the game board (presentation-only module).
##
## ONE directional graph, ONE cursor: playmat slots, hand cards, action-panel
## buttons, hand-button stacks, system buttons, the log/chat panel, tracker
## labels and choice buttons are all nodes of the BoardNavGraph adjacency map
## (CursorMap resolves it, tie-breaking multi-target directions by the
## last-10-visited history). Cards, slots AND buttons keep their pointer
## picking and never receive Godot focus — on pad_confirm this module
## synthesizes the exact signals the pointer path emits (select_card_at,
## Slot.simulate_click, Button.pressed).
##
## THE FOCUS INVARIANT: while the board is the top focus context, NO control
## holds real focus (the context provider always answers null) — otherwise
## the mirrored ui_* events would double-drive the focused control. Real
## focus exists only inside registered modals/menus and, deliberately, the
## chat LineEdit while typing (fenced by GamepadInput's text-editing guard).
##
## SelectionController.selection_context_changed jails the cursor to the
## active prompt's elements; the map's skip-through rule keeps movement
## spatial between valid stops. The bumpers jump to the peripheral modules
## (LB = game log/chat, RB = turn tracker) and work DURING prompts — the
## jail is suspended while bumper focus is active and restored on return.
##
## Overlays suspend the module (same visibility set as game_board's
## ui_cancel ladder); registered modal dialogs suspend it via the focus
## context stack.
##
## Never loaded by the harness stub or headless server board — no RPC-surface
## impact.

## Emitted on every cursor move, context change and bumper transition —
## consumed by NavDebugOverlay and the UI tests.
signal nav_state_changed

const CURSOR_COLOR := Color(0.35, 1.0, 0.55, 0.95)
const CURSOR_PAD := 4.0
const DEFAULT_ELEMENT := "bot_z2"
## Where the cursor first lands when the gamepad takes over in free browse.
const BROWSE_DEFAULT := "ap_end_main"
const ZONE_MODES: Array[String] = ["card_to_zone", "zone_target", "zones_target", "strategy_target"]
const LOG_SCROLL_LINES := 3
## Frames after the device flips to gamepad mode during which pad_* actions
## are swallowed: the physical press that switched modes injects its logical
## twin a frame later, which must not activate the element the cursor just
## landed on (with buttons as graph nodes, that twin would e.g. press End
## Main). The switching press only wakes the cursor.
const TAKEOVER_GRACE_FRAMES := 2

var _board: Node
## Current graph node id ("" = cursor parked; pointer is the active device).
var _element: String = ""
var _map: CursorMap = CursorMap.new({})
var _mode: String = "none"
var _ctx_valid: Array[int] = []
var _ctx_board_pid: int = -1
var _ctx_hand_pid: int = -1
## Prompt jail for zone/strategy modes: element ids the cursor may rest on.
var _ctx_elements: Dictionary = {}
var _cursor: Panel = null
var _previewing_card: bool = false
## Card under the hand cursor — survives reorders (sorting rewrites the
## numeric index but the card ref stays valid).
var _cursor_card: Control = null
## Hand card currently raised by the cursor (drives the same hover tween the
## mouse uses via card._on_mouse_entered/_on_mouse_exited).
var _hovered_card: Control = null
## Choice button under the cursor (synthesized mouse_entered/exited drive the
## same preview-retarget handlers the pointer path uses).
var _hovered_choice: Button = null
## Armed by a hand-initiated play: when the selection context clears, the
## cursor returns to the hand (left neighbor -> right neighbor -> Sort)
## instead of staying on the action panel.
var _pending_hand_return := false
var _play_origin_index := 0
var _play_origin_card: Control = null
## Bumper focus state: {"element": id to return to, "target": "log"|"tracker"}.
## Empty = no bumper focus active.
var _bumper_return: Dictionary = {}
## Whether RB temporarily un-collapsed a prompt-collapsed tracker.
var _tracker_uncollapsed := false
## Process frame of the last pointer->gamepad switch (see TAKEOVER_GRACE_FRAMES).
var _takeover_frame := -TAKEOVER_GRACE_FRAMES - 1


func _ready() -> void:
	_board = get_parent()
	GamepadHelper.gamepad_detected.connect(_on_gamepad_detected)
	GamepadHelper.pointer_detected.connect(_on_pointer_detected)
	# THE FOCUS INVARIANT: the board's focus context always answers null.
	GamepadHelper.push_focus_context(_board, func() -> Control: return null)
	var selection: SelectionController = _board.get_node_or_null("SelectionController")
	if selection:
		selection.selection_context_changed.connect(_on_selection_context_changed)
		selection.action_buttons_changed.connect(_on_action_buttons_changed)
	var mobile: Node = _board.get_node_or_null("MobileLayout")
	if mobile and mobile.has_signal("fab_toggled"):
		mobile.fab_toggled.connect(_on_fab_toggled)
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
	if int(Engine.get_process_frames()) <= _takeover_frame + TAKEOVER_GRACE_FRAMES:
		return # The mode-switching press only wakes the cursor.
	if event.is_action_pressed("pad_focus_log"):
		_bumper("log")
	elif event.is_action_pressed("pad_focus_tracker"):
		_bumper("tracker")
	elif event.is_action_pressed("pad_end_main"):
		_board._selection.press_primary_button()
	elif event.is_action_pressed("pad_play_card_invasion"):
		_try_play_hovered(CardEnums.ActionType.INVADE)
	elif event.is_action_pressed("pad_play_card_rage"):
		_try_play_hovered(CardEnums.ActionType.GAIN_RAGE)
	elif event.is_action_pressed("pad_menu"):
		if _board._leave_dialog:
			_board._leave_dialog.popup_centered()
	elif event.is_action_pressed("pad_chat"):
		_open_chat()
	elif event.is_action_pressed("pad_nav_left"):
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
	get_viewport().set_input_as_handled()


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


# --- Graph lifecycle ---

## Rebuild the adjacency map from the live board (hand size, choice buttons,
## layout). Cheap (~70 small dict entries), runs at the top of every input
## action; CursorMap keeps its visited history across swaps.
func _rebuild_map() -> void:
	_map.set_map(BoardNavGraph.build({
		"mobile": _board._is_mobile_layout,
		"hand_count": _hand_mgr().managed_cards.size() if _hand_mgr() else 0,
		"tracker_count": _tracker_labels().size(),
		"choice_count": _choice_buttons().size(),
		"rect_of": _rect_of,
	}))


func _rect_of(id: String) -> Rect2:
	var control := _resolve_control(id)
	return control.get_global_rect() if control and control.is_inside_tree() else Rect2()


# --- Device / context transitions ---

func _on_gamepad_detected() -> void:
	_takeover_frame = int(Engine.get_process_frames())
	_rebuild_map()
	if _mode != "none":
		_apply_context()
	elif _element != "" and _element_valid(_element):
		_update_cursor()
	else:
		_relocate_cursor([BROWSE_DEFAULT, DEFAULT_ELEMENT])


func _on_pointer_detected() -> void:
	_pending_hand_return = false
	_bumper_return.clear()
	_element = ""
	_hide_cursor()
	nav_state_changed.emit()


func _on_selection_context_changed(ctx: Dictionary) -> void:
	_mode = ctx.get("mode", "none")
	_ctx_valid = ctx.get("valid", [] as Array[int])
	_ctx_board_pid = ctx.get("board_pid", -1)
	_ctx_hand_pid = ctx.get("hand_pid", -1)
	_rebuild_ctx_elements()
	if not GamepadHelper.is_using_gamepad():
		return
	_apply_context()


## The action-button set changed under the cursor (enable/disable/visibility
## churn after every action) — revalidate instead of yanking focus around.
func _on_action_buttons_changed() -> void:
	if not GamepadHelper.is_using_gamepad() or _element == "":
		return
	_rebuild_map()
	if not _element_valid(_element):
		_relocate_cursor([BROWSE_DEFAULT, DEFAULT_ELEMENT])
	else:
		_update_cursor()


## Mobile FAB expand/collapse: the grid buttons are only mapped while
## expanded — move the cursor in on expand, back out on collapse.
func _on_fab_toggled(expanded: bool) -> void:
	if not _is_active():
		return
	_rebuild_map()
	if expanded:
		for id in ["ap_play_battle", "ap_play_monster", "ap_play_strategy", "ap_gain_rage", "ap_invade"]:
			if _element_valid(id):
				_enter_element(id)
				return
		_enter_element("ap_fab_main")
	elif not _element_valid(_element):
		_relocate_cursor([BROWSE_DEFAULT, DEFAULT_ELEMENT])


## Translate the prompt context into the set of map elements the cursor may
## rest on (zone/strategy modes only — the other modes jail by id prefix in
## _jail_allows). Empty = free browse.
func _rebuild_ctx_elements() -> void:
	_ctx_elements.clear()
	match _mode:
		"card_to_zone", "zone_target", "zones_target":
			var side := _side_for_pid(_ctx_board_pid)
			for zone_idx in _ctx_valid:
				_ctx_elements["%s_z%d" % [side, zone_idx + 1]] = true
		"strategy_target":
			var side := _side_for_pid(_ctx_board_pid)
			for strat_idx in _ctx_valid:
				_ctx_elements["%s_strategy_%d" % [side, strat_idx]] = true


func _apply_context() -> void:
	# A context change while bumper focus is active force-returns first — the
	# new prompt's jail decides where the cursor may sit.
	if not _bumper_return.is_empty():
		_bumper_exit(false)
	_rebuild_map()
	match _mode:
		"hand_select", "hand_discard":
			var valid := _hand_valid_indices()
			if valid.is_empty():
				_hide_cursor()
			elif _hand_index() in valid:
				_update_cursor()
			else:
				_enter_element("hand_%d" % valid[0])
		"card_to_zone", "zone_target", "zones_target", "strategy_target":
			var first := _first_ctx_element()
			if first != "":
				_enter_element(first)
		"choice":
			if not _choice_buttons().is_empty():
				_enter_element("choice_0")
		"confirm":
			_enter_element("ap_confirm")
		_:
			if _pending_hand_return:
				_pending_hand_return = false
				_return_cursor_to_hand_after_play()
			elif _element == "" or not _element_valid(_element):
				_relocate_cursor([BROWSE_DEFAULT, DEFAULT_ELEMENT])
			else:
				_update_cursor()
	nav_state_changed.emit()


func _first_ctx_element() -> String:
	# Keep the cursor where it is when it's already on a valid element.
	if _ctx_elements.has(_element):
		return _element
	var ids: Array = _ctx_elements.keys()
	ids.sort()
	for id: String in ids:
		if _element_valid(id):
			return id
	return ""


## Deterministic relocation when the element under the cursor disappears:
## most recent valid history entry, then any spatial neighbor, then the
## given fallbacks. Never grabs real focus.
func _relocate_cursor(fallbacks: Array) -> void:
	var hist := _map.visited()
	for i in range(hist.size() - 1, -1, -1):
		if hist[i] != _element and _element_valid(hist[i]):
			_enter_element(hist[i])
			return
	if _element != "":
		for dir in ["right", "left", "up", "down"]:
			var target := _map.next(_element, dir, _element_valid)
			if target != "":
				_enter_element(target)
				return
	for id: String in fallbacks:
		if _element_valid(id):
			_enter_element(id)
			return
	_hide_cursor()


# --- Movement ---

func _move(dir: String) -> void:
	_rebuild_map()
	if _element == "":
		_relocate_cursor([BROWSE_DEFAULT, DEFAULT_ELEMENT])
		return
	# On the log panel the dpad scrolls the log text; left/right (and the
	# graph edges) leave it.
	if _element == "log_panel" and (dir == "up" or dir == "down"):
		_board._log_chat.scroll_log(-LOG_SCROLL_LINES if dir == "up" else LOG_SCROLL_LINES)
		return
	var target := _map.next(_element, dir, _element_valid)
	if target == "" and (dir == "left" or dir == "right") and _mode in ZONE_MODES:
		# Prompt jail: a sparse valid set can dead-end the spatial graph
		# (e.g. Z2/Z4/Z6 span both rows). Left/right then cycle the valid
		# elements so every legal target stays reachable.
		target = _ctx_cycle(1 if dir == "right" else -1)
	if target == "":
		return
	# Walking out of the bumper region resumes normal browsing: B goes back
	# to meaning "cancel". (Jailed prompts can't walk out — _jail_allows.)
	if not _bumper_return.is_empty() and not _in_bumper_region(target):
		_bumper_exit_cleanup()
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


func _enter_element(id: String) -> void:
	_clear_preview()
	_element = id
	_map.push_visited(id)
	_update_cursor()
	nav_state_changed.emit()


# --- Validity ---

## Whether the cursor may rest on `id`: the active jail (prompt mode or
## bumper focus) first, then the element's own visibility/enabled state.
func _element_valid(id: String) -> bool:
	return _jail_allows(id) and _element_usable(id)


func _jail_allows(id: String) -> bool:
	# Bumper focus suspends the prompt jail but restricts movement to the
	# bumper region's own nodes; in free browse the rest of the graph stays
	# open (walking out simply clears the return point).
	if not _bumper_return.is_empty():
		if _in_bumper_region(id):
			return true
		if _mode != "none":
			return false
	match _mode:
		"hand_select", "hand_discard":
			return id.begins_with("hand_")
		"card_to_zone", "zone_target", "zones_target", "strategy_target":
			return _ctx_elements.has(id)
		"choice":
			return id.begins_with("choice_")
		"confirm":
			return id == "ap_confirm" or id == "ap_cancel"
	return true


func _element_usable(id: String) -> bool:
	if id.begins_with("hand_"):
		return _id_index(id) in _hand_valid_indices()
	if id.begins_with("trk_"):
		var labels := _tracker_labels()
		var i := _id_index(id)
		return i < labels.size() and labels[i].is_visible_in_tree()
	if id.begins_with("choice_"):
		var buttons := _choice_buttons()
		var i := _id_index(id)
		return i < buttons.size() and buttons[i].is_visible_in_tree() and not buttons[i].disabled
	if id == "log_panel":
		# Mobile: always reachable — the bumper slides the tray in.
		if _board._is_mobile_layout:
			return true
	var control := _resolve_control(id)
	if control == null or not control.is_visible_in_tree():
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	return true


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


# --- Bumper jumps (LB = log/chat, RB = turn tracker) ---

func _bumper(target: String) -> void:
	if not _bumper_return.is_empty():
		if _bumper_return.get("target", "") == target:
			_bumper_exit(true)
			return
		# The other bumper switches targets; the return point is preserved.
		_bumper_return["target"] = target
		_leave_bumper_region(_other_bumper(target))
		_enter_bumper_region(target)
		return
	_bumper_return = {"element": _element, "target": target}
	_enter_bumper_region(target)


## B (via the board's ui_cancel ladder) returns the cursor from bumper focus.
## Returns false when there is nothing to consume.
func consume_cancel_for_bumper_return() -> bool:
	if _bumper_return.is_empty() or not _is_active():
		return false
	_bumper_exit(true)
	return true


func _enter_bumper_region(target: String) -> void:
	if target == "log":
		if _board._is_mobile_layout:
			_mobile().set_log_tray_open(true)
		_board._log_chat.set_cursor_hover(true)
		_rebuild_map()
		_enter_element("log_panel")
		return
	# Turn tracker: temporarily un-collapse a prompt-collapsed tracker so RB
	# never feels dead; restored on return.
	if _board._is_mobile_layout:
		_mobile().set_tracker_tray_open(true)
	elif _board._tracker._collapsed:
		_board._tracker.set_collapsed(false)
		_tracker_uncollapsed = true
	_rebuild_map()
	var labels := _tracker_labels()
	if labels.is_empty():
		return
	# Re-enter at the last visited label (history), else the top one.
	var hist := _map.visited()
	for i in range(hist.size() - 1, -1, -1):
		if hist[i].begins_with("trk_") and _element_valid(hist[i]):
			_enter_element(hist[i])
			return
	_enter_element("trk_0")


func _bumper_exit(move_back: bool) -> void:
	var back: String = _bumper_return.get("element", "")
	_bumper_exit_cleanup()
	if not move_back:
		return
	_rebuild_map()
	if back != "" and _element_valid(back):
		_enter_element(back)
	else:
		_relocate_cursor([BROWSE_DEFAULT, DEFAULT_ELEMENT])
	nav_state_changed.emit()


## Close trays / restore collapse without moving the cursor.
func _bumper_exit_cleanup() -> void:
	var target: String = _bumper_return.get("target", "")
	_bumper_return.clear()
	_leave_bumper_region(target)


func _leave_bumper_region(target: String) -> void:
	if target == "log":
		_board._log_chat.set_cursor_hover(false)
		if _board._is_mobile_layout:
			_mobile().set_log_tray_open(false)
	elif target == "tracker":
		if _board._is_mobile_layout:
			_mobile().set_tracker_tray_open(false)
		elif _tracker_uncollapsed:
			_tracker_uncollapsed = false
			_board._update_tracker_collapse()


func _in_bumper_region(id: String) -> bool:
	return id == "log_panel" or id.begins_with("trk_")


func _other_bumper(target: String) -> String:
	return "tracker" if target == "log" else "log"


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


## id -> {kind, control, idx, pid}; {} for unknown ids. Playmat ids resolve
## through the seat boards; UI ids through the board's button refs and the
## module-owned dynamic lists (hand cards, tracker labels, choice buttons).
func _resolve(id: String) -> Dictionary:
	if id.begins_with("hand_"):
		var card := _hand_card(_id_index(id))
		return {"kind": "hand", "control": card, "idx": _id_index(id), "pid": _hand_pid()} if card else {}
	if id.begins_with("trk_"):
		var labels := _tracker_labels()
		var i := _id_index(id)
		return {"kind": "tracker", "control": labels[i], "idx": i, "pid": -1} if i < labels.size() else {}
	if id.begins_with("choice_"):
		var buttons := _choice_buttons()
		var i := _id_index(id)
		return {"kind": "choice", "control": buttons[i], "idx": i, "pid": -1} if i < buttons.size() else {}
	if id == "log_panel":
		var panel: Control = _board.get_node_or_null("LogPanel")
		return {"kind": "log", "control": panel, "idx": 0, "pid": -1} if panel else {}
	if id.begins_with("ap_") or id.begins_with("sys_"):
		var btn := _ui_button(id)
		return {"kind": "button", "control": btn, "idx": 0, "pid": -1} if btn else {}
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


func _ui_button(id: String) -> Control:
	match id:
		"ap_cancel": return _board.btn_cancel
		"ap_confirm": return _board.btn_confirm
		"ap_play_battle": return _board.btn_play_battle
		"ap_play_strategy": return _board.btn_play_strategy
		"ap_gain_rage": return _board.btn_gain_rage
		"ap_play_monster": return _board.btn_play_monster
		"ap_invade": return _board.btn_invade
		"ap_end_main": return _board.btn_end_main
		"ap_hand_toggle": return _board.hand_toggle_button
		"ap_sort_hand": return _board.sort_hand_button
		"ap_opp_hand_toggle": return _board.opponent_hand_toggle_button
		"ap_opp_sort_hand": return _board.opponent_sort_hand_button
		"ap_fab_main": return _mobile().fab_main_button() if _board._is_mobile_layout else null
		"sys_bug_report": return _board.btn_bug_report
		"sys_concede": return _board.btn_concede
		"sys_main_menu": return _board.btn_main_menu
		"sys_sound": return _board.btn_sound_toggle
		"sys_music": return _board.btn_music_toggle
		"sys_export_log": return _board.btn_export_log
	return null


func _resolve_control(id: String) -> Control:
	return _resolve(id).get("control") as Control


# --- Activation ---

## Play the hovered hand card via the given action — same flow as pressing
## the action button and clicking the card (SelectionController does all
## gating). No-op outside free hand browsing.
func _try_play_hovered(action: CardEnums.ActionType) -> void:
	if not _element.begins_with("hand_") or _mode != "none":
		return
	var index := _hand_index()
	var card := _hand_card(index)
	if card == null:
		return
	# Unhover before any reparent the play may trigger (hover tween gotcha).
	_set_hovered_card(null)
	if _board._selection.play_card_from_hand(card, action):
		_pending_hand_return = true
		_play_origin_index = index
		_play_origin_card = card
	else:
		_update_cursor() # rejected: re-hover in place


func _confirm() -> void:
	_rebuild_map()
	if _element.begins_with("hand_"):
		var hand := _hand_mgr()
		if hand and hand.selection_mode:
			hand.select_card_at(_hand_index())
		elif _mode == "none":
			# Browse: A plays the hovered card according to its type.
			var card := _hand_card(_hand_index())
			if card and "card_data" in card:
				match int(card.card_data.get("card_type", -1)):
					CardEnums.CardType.MONSTER:
						_try_play_hovered(CardEnums.ActionType.PLAY_MONSTER)
					CardEnums.CardType.BATTLE:
						_try_play_hovered(CardEnums.ActionType.PLAY_BATTLE)
					CardEnums.CardType.STRATEGY:
						_try_play_hovered(CardEnums.ActionType.PLAY_STRATEGY)
		return
	var entry := _resolve(_element)
	if entry.is_empty():
		return
	match entry["kind"]:
		"button", "choice":
			_activate_button(entry["control"] as BaseButton)
			return
		"log":
			_open_chat()
			return
		"tracker":
			_board._tracker.toggle_label(entry["control"] as Label)
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


## Press a button the way the pointer does — pressed.emit(), never
## grab_focus (THE FOCUS INVARIANT).
func _activate_button(btn: BaseButton) -> void:
	if btn and btn.is_visible_in_tree() and not btn.disabled:
		btn.pressed.emit()


func _inspect() -> void:
	if _element.begins_with("hand_"):
		var card := _hand_card(_hand_index())
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
	_board._log_chat.focus_chat()


# --- Cursor visual ---

## Sorting/reordering rewrites managed_cards; keep the cursor on the SAME
## card by rebinding the numeric index to the remembered card ref.
func _on_hand_reordered(hand: CardManager) -> void:
	if not _element.begins_with("hand_") or hand != _hand_mgr():
		return
	# arrange_cards re-stamps fan z-indexes over the raised card — drop the
	# hover so _update_cursor re-applies it cleanly on the rebound card.
	_set_hovered_card(null)
	_rebuild_map()
	if is_instance_valid(_cursor_card):
		var idx := hand.managed_cards.find(_cursor_card)
		if idx >= 0:
			_element = "hand_%d" % idx
			_map.push_visited(_element)
			_update_cursor()
			nav_state_changed.emit()
			return
	# The cursor's card left the hand (played/discarded): move to the card on
	# its LEFT, else the one that slid into its slot from the right, else the
	# Sort button.
	var valid := _hand_valid_indices()
	if valid.is_empty():
		_enter_element("ap_sort_hand")
		return
	var origin := _hand_index()
	var left := origin - 1
	while left >= 0 and left not in valid:
		left -= 1
	if left >= 0:
		_enter_element("hand_%d" % left)
		return
	var right := origin
	while right < hand.managed_cards.size() and right not in valid:
		right += 1
	_enter_element("hand_%d" % (right if right in valid else valid[0]))


## After a hand-initiated play resolves: back into the hand on the played
## card's LEFT neighbor, else the card that slid into its slot, else the
## Sort button. If the card is somehow still in the hand (play cancelled or
## the visual removal lags), the cursor sits back on it and the
## cards_reordered rule finishes the job when it actually leaves.
func _return_cursor_to_hand_after_play() -> void:
	var hand := _hand_mgr()
	_rebuild_map()
	if hand == null:
		_relocate_cursor([BROWSE_DEFAULT, DEFAULT_ELEMENT])
		return
	var idx := hand.managed_cards.find(_play_origin_card) if is_instance_valid(_play_origin_card) else -1
	if idx < 0:
		if hand.managed_cards.is_empty():
			_enter_element("ap_sort_hand")
			return
		if _play_origin_index > 0:
			idx = mini(_play_origin_index - 1, hand.managed_cards.size() - 1)
		else:
			idx = mini(_play_origin_index, hand.managed_cards.size() - 1)
	_enter_element("hand_%d" % idx)


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
	_cursor_card = target if _element.begins_with("hand_") else null
	_set_hovered_card(_cursor_card)
	_set_hovered_choice(target as Button if _element.begins_with("choice_") else null)
	var rect := target.get_global_rect()
	_cursor.visible = true
	_cursor.global_position = rect.position - Vector2(CURSOR_PAD, CURSOR_PAD)
	_cursor.size = rect.size + Vector2(CURSOR_PAD, CURSOR_PAD) * 2.0
	_refresh_preview()


## The controller cursor raises the hovered hand card exactly like the mouse
## does — same enter/exit handlers, same tween, same restore.
func _set_hovered_card(card: Control) -> void:
	if card == _hovered_card:
		return
	if is_instance_valid(_hovered_card):
		_hovered_card._on_mouse_exited()
	_hovered_card = card
	if is_instance_valid(card):
		card._on_mouse_entered()


## Choice buttons keep their pointer hover handlers (preview retarget +
## board pulse) — the cursor synthesizes the same enter/exit signals.
func _set_hovered_choice(btn: Button) -> void:
	if btn == _hovered_choice:
		return
	if is_instance_valid(_hovered_choice):
		_hovered_choice.mouse_exited.emit()
	_hovered_choice = btn
	if is_instance_valid(btn):
		btn.mouse_entered.emit()


## Hand cards move under the cursor (hover raise, sort/arrange tweens) —
## track the ring to the card's live rect every frame.
func _process(_delta: float) -> void:
	if not _element.begins_with("hand_") or _cursor == null or not _cursor.visible:
		return
	if not is_instance_valid(_cursor_card):
		return
	var rect := _cursor_card.get_global_rect()
	_cursor.global_position = rect.position - Vector2(CURSOR_PAD, CURSOR_PAD)
	_cursor.size = rect.size + Vector2(CURSOR_PAD, CURSOR_PAD) * 2.0


func _hide_cursor() -> void:
	_clear_preview()
	_set_hovered_card(null)
	_set_hovered_choice(null)
	if _cursor:
		_cursor.visible = false


func _cursor_target() -> Control:
	return _resolve_control(_element) if _element != "" else null


## Mirror the pointer hover behavior: the card under the cursor shows in the
## big right-side preview panel (top card of zone / strategy slots and the
## discard pile; hand cards raise in place instead).
func _refresh_preview() -> void:
	var data := _cursor_preview_data()
	if data.is_empty():
		_clear_preview()
		return
	_board._show_card_preview(data)
	_previewing_card = true


func _cursor_preview_data() -> Dictionary:
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

func _id_index(id: String) -> int:
	return id.get_slice("_", id.get_slice_count("_") - 1).to_int()


## The hand index under the cursor (0 when the cursor is not on the hand).
func _hand_index() -> int:
	return _id_index(_element) if _element.begins_with("hand_") else 0


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


func _mobile() -> Node:
	return _board.get_node_or_null("MobileLayout")


func _tracker_labels() -> Array[Label]:
	var tracker: Node = _board.get_node_or_null("TurnTrackerModule")
	if tracker == null:
		return [] as Array[Label]
	return tracker.interactive_labels()


func _choice_buttons() -> Array[Button]:
	var selection: Node = _board.get_node_or_null("SelectionController")
	if selection == null:
		return [] as Array[Button]
	return selection._choice_buttons


# --- Debug accessors (read-only; consumed by NavDebugOverlay) ---

func debug_state() -> Dictionary:
	return {
		"element": _element,
		"mode": _mode,
		"ctx": _ctx_elements.keys(),
		"pending_hand_return": _pending_hand_return,
		"bumper_return": _bumper_return.duplicate(),
		"active": _is_active(),
	}


## The live graph annotated per node with its rect and validity — everything
## the overlay needs to paint without re-deriving nav rules.
func debug_graph() -> Dictionary:
	_rebuild_map()
	var graph := BoardNavGraph.build({
		"mobile": _board._is_mobile_layout,
		"hand_count": _hand_mgr().managed_cards.size() if _hand_mgr() else 0,
		"tracker_count": _tracker_labels().size(),
		"choice_count": _choice_buttons().size(),
		"rect_of": _rect_of,
	})
	var out := {}
	for id: String in graph:
		out[id] = {
			"edges": graph[id],
			"rect": _rect_of(id),
			"usable": _element_usable(id),
			"jailed_out": not _jail_allows(id),
		}
	return out
