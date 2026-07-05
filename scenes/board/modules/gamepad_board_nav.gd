class_name GamepadBoardNav
extends Node
## Controller navigation for the game board (presentation-only module).
##
## Cards and slots keep their custom pointer picking and never receive Godot
## focus — this module moves a visual cursor through *virtual regions* (hand,
## own zones, opponent zones, strategy slots) and, on pad_confirm, synthesizes
## the exact signals the pointer path emits (CardManager.select_card_at,
## Slot.simulate_click, SelectionController.play_selected_card_to_zone).
## The ACTION_PANEL region hands control to Godot's real focus system so
## ui_accept drives the buttons natively.
##
## SelectionController.selection_context_changed jails the cursor to the
## active prompt's region and valid indices (the RestrictControllerNavigation
## idea from Slay the Spire 2). Overlays suspend the module: the same
## visibility set as game_board's ui_cancel ladder.
##
## Never loaded by the harness stub or headless server board — no RPC-surface
## impact.

enum Region { NONE, HAND, MY_ZONES, OPP_ZONES, STRATEGY, ACTION_PANEL }

const CURSOR_COLOR := Color(0.35, 1.0, 0.55, 0.95)
const CURSOR_PAD := 4.0

var _board: Node
var _region: int = Region.NONE
var _index: int = 0
var _mode: String = "none"
var _ctx_valid: Array[int] = []
var _ctx_board_pid: int = -1
var _ctx_hand_pid: int = -1
var _cursor: Panel = null
var _previewing_hand_card: bool = false


func _ready() -> void:
	_board = get_parent()
	GamepadHelper.gamepad_detected.connect(_on_gamepad_detected)
	GamepadHelper.pointer_detected.connect(_on_pointer_detected)
	GamepadHelper.push_focus_context(_board, _default_focus_control)
	var selection: SelectionController = _board.get_node_or_null("SelectionController")
	if selection:
		selection.selection_context_changed.connect(_on_selection_context_changed)


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
	elif _region != Region.NONE and _region != Region.ACTION_PANEL:
		if event.is_action_pressed("pad_nav_left"):
			_move(-1)
		elif event.is_action_pressed("pad_nav_right"):
			_move(1)
		elif event.is_action_pressed("pad_nav_up"):
			_vertical_region(1)
		elif event.is_action_pressed("pad_nav_down"):
			_vertical_region(-1)
		elif event.is_action_pressed("pad_confirm"):
			_confirm()
		elif event.is_action_pressed("pad_inspect"):
			_inspect()
		else:
			return
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


# --- Device / context transitions ---

func _on_gamepad_detected() -> void:
	if _mode != "none":
		_apply_context()
	else:
		_enter_region(Region.ACTION_PANEL)


func _on_pointer_detected() -> void:
	_region = Region.NONE
	_hide_cursor()


func _on_selection_context_changed(ctx: Dictionary) -> void:
	_mode = ctx.get("mode", "none")
	_ctx_valid = ctx.get("valid", [] as Array[int])
	_ctx_board_pid = ctx.get("board_pid", -1)
	_ctx_hand_pid = ctx.get("hand_pid", -1)
	if not GamepadHelper.is_using_gamepad():
		return
	_apply_context()


func _apply_context() -> void:
	match _mode:
		"hand_select", "hand_discard":
			_enter_region(Region.HAND)
		"card_to_zone", "zone_target", "zones_target":
			_enter_region(Region.MY_ZONES if _ctx_board_pid == _my_pid() else Region.OPP_ZONES)
		"strategy_target":
			_enter_region(Region.STRATEGY)
		"choice", "confirm":
			# Real focus takes over (choice buttons / the Confirm button).
			_region = Region.NONE
			_hide_cursor()
			if _mode == "confirm":
				GamepadHelper.refocus()
		_:
			_enter_region(Region.ACTION_PANEL)


# --- Regions & movement ---

func _cycle_region(dir: int) -> void:
	if _mode != "none":
		return # Prompts jail the cursor to their region
	var order: Array[int] = [Region.ACTION_PANEL, Region.HAND, Region.MY_ZONES, Region.OPP_ZONES]
	var at := order.find(_region)
	var next: int = order[(at + dir + order.size()) % order.size()] if at >= 0 else Region.HAND
	_enter_region(next)


## Browsing only: dpad up/down walks HAND -> MY_ZONES -> OPP_ZONES.
func _vertical_region(dir: int) -> void:
	if _mode != "none":
		return
	var ladder: Array[int] = [Region.HAND, Region.MY_ZONES, Region.OPP_ZONES]
	var at := ladder.find(_region)
	if at < 0:
		return
	var next_at: int = clampi(at + dir, 0, ladder.size() - 1)
	if next_at != at:
		_enter_region(ladder[next_at])


func _enter_region(region: int) -> void:
	_clear_hand_preview()
	_region = region
	if region == Region.ACTION_PANEL or region == Region.NONE:
		_hide_cursor()
		GamepadHelper.refocus()
		return
	# Virtual region: the module owns input; no control may hold focus or the
	# mirrored ui_* events would double-drive it.
	get_viewport().gui_release_focus()
	var valid := _valid_indices()
	if valid.is_empty():
		_hide_cursor()
		return
	_index = valid[0] if _index not in valid else _index
	_update_cursor()


func _move(dir: int) -> void:
	var valid := _valid_indices()
	if valid.is_empty():
		return
	var at := valid.find(_index)
	_index = valid[(at + dir + valid.size()) % valid.size()] if at >= 0 else valid[0]
	_update_cursor()


func _valid_indices() -> Array[int]:
	var out: Array[int] = []
	match _region:
		Region.HAND:
			var hand := _hand_mgr()
			if hand == null:
				return out
			if hand.selection_mode and not hand.selectable_indices.is_empty():
				return hand.selectable_indices.duplicate()
			for i in range(hand.managed_cards.size()):
				out.append(i)
		Region.MY_ZONES, Region.OPP_ZONES:
			if _mode != "none":
				return _ctx_valid.duplicate()
			for i in range(8):
				out.append(i)
		Region.STRATEGY:
			return _ctx_valid.duplicate()
	return out


# --- Activation ---

func _confirm() -> void:
	match _region:
		Region.HAND:
			var hand := _hand_mgr()
			if hand and hand.selection_mode:
				hand.select_card_at(_index)
		Region.MY_ZONES, Region.OPP_ZONES:
			if _mode == "card_to_zone":
				_board._selection.play_selected_card_to_zone(_index)
			elif _mode == "zone_target" or _mode == "zones_target":
				var slot := _zone_slot(_index)
				if slot:
					slot.simulate_click()
					_update_cursor() # zones_target keeps selecting after a toggle
		Region.STRATEGY:
			var slot := _strategy_slot(_index)
			if slot:
				slot.simulate_click()


func _inspect() -> void:
	match _region:
		Region.HAND:
			var card := _hand_card(_index)
			if card and "card_data" in card:
				_board._show_card_zoom(card.card_data)
		Region.MY_ZONES, Region.OPP_ZONES:
			_board._on_zone_slot_right_clicked(_index + 1, _region_pid())


func _open_chat() -> void:
	if _board._is_mobile_layout:
		_board._notify_mobile_log_chat()
	elif _board.chat_input and _board.chat_input.is_visible_in_tree():
		_board.chat_input.grab_focus()


# --- Cursor visual ---

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
	var rect := target.get_global_rect()
	_cursor.visible = true
	_cursor.global_position = rect.position - Vector2(CURSOR_PAD, CURSOR_PAD)
	_cursor.size = rect.size + Vector2(CURSOR_PAD, CURSOR_PAD) * 2.0
	_refresh_hand_preview()


func _hide_cursor() -> void:
	_clear_hand_preview()
	if _cursor:
		_cursor.visible = false


func _cursor_target() -> Control:
	match _region:
		Region.HAND:
			return _hand_card(_index)
		Region.MY_ZONES, Region.OPP_ZONES:
			return _zone_slot(_index)
		Region.STRATEGY:
			return _strategy_slot(_index)
	return null


## Mirror the pointer hover behavior: the card under the cursor shows in the
## big right-side preview panel.
func _refresh_hand_preview() -> void:
	if _region != Region.HAND:
		_clear_hand_preview()
		return
	var card := _hand_card(_index)
	if card and "card_data" in card and not card.card_data.is_empty():
		_board._show_card_preview(card.card_data)
		_previewing_hand_card = true


func _clear_hand_preview() -> void:
	if _previewing_hand_card:
		_board._hide_card_preview()
		_previewing_hand_card = false


# --- Lookups ---

func _my_pid() -> int:
	if _board.is_multiplayer_game:
		return _board.local_player_id
	return _board._get_current_pid()


func _region_pid() -> int:
	if _mode != "none" and _ctx_board_pid >= 0:
		return _ctx_board_pid
	return _my_pid() if _region == Region.MY_ZONES else 1 - _my_pid()


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


func _zone_slot(index: int) -> Slot:
	var board := _player_board(_region_pid())
	if board == null or index < 0 or index >= board.zone_slots.size():
		return null
	return board.zone_slots[index]


func _strategy_slot(index: int) -> Slot:
	var board := _player_board(_ctx_board_pid if _ctx_board_pid >= 0 else _my_pid())
	if board == null or index < 0 or index >= board.strategy_slots.size():
		return null
	return board.strategy_slots[index]


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
