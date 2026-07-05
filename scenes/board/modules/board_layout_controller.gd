class_name BoardLayoutController
extends Node
## Desktop board arrangement: local-player mirroring, hand positioning, button text fitting, hand collapse/expand.
## Method bodies moved verbatim from game_board.gd (Phase 8 split);
## remaining board state/methods are reached via `_board`. The board
## keeps one-line delegates, so call sites, signal connections, and the
## session-layer `_board.*` contract are unchanged.

var _board: GameBoard


func _ready() -> void:
	_board = get_parent() as GameBoard


func _arrange_for_local_player() -> void:
	if _board.local_player_id != 1:
		return

	var board_column := _board.get_node("VBoxContainer/BoardArea/BoardColumn")

	# Swap hand spaces and boards: local (P2) to bottom, opponent (P1) to top
	# Default order: P2HandSpace(0), P2Board(1), Divider(2), P1Board(3), P1HandSpace(4)
	# Target order:  P1HandSpace(0), P1Board(1), Divider(2), P2Board(3), P2HandSpace(4)
	var divider := board_column.get_node("Divider")
	board_column.move_child(_board.player1_hand_space, 0)
	board_column.move_child(_board.player1_board, 1)
	board_column.move_child(divider, 2)
	board_column.move_child(_board.player2_board, 3)
	board_column.move_child(_board.player2_hand_space, 4)

	# Toggle mirroring (P1 now at top needs mirroring, P2 at bottom doesn't)
	_board.player1_board.toggle_mirrored()
	_board.player2_board.toggle_mirrored()

	# Swap turn tracker: local player (P2) to bottom, opponent (P1) to top
	var tracker := _board.get_node("VBoxContainer/BoardArea/RightSpacer/TurnTracker")
	var children: Array[Node] = []
	for child in tracker.get_children():
		children.append(child)
	var sep_idx := -1
	for i in range(children.size()):
		if children[i].name == "Separator":
			sep_idx = i
			break
	# Reorder: P1 section, separator, P2 section
	var new_order: Array[Node] = []
	new_order.append_array(children.slice(sep_idx + 1))
	new_order.append(children[sep_idx])
	new_order.append_array(children.slice(0, sep_idx))
	for i in range(new_order.size()):
		tracker.move_child(new_order[i], i)


func _position_hands() -> void:
	var local_hand: Node2D
	var local_space: Control
	var opponent_hand: Node2D
	var opponent_space: Control

	if _board.local_player_id == 0:
		local_hand = _board.player1_hand
		local_space = _board.player1_hand_space
		opponent_hand = _board.player2_hand
		opponent_space = _board.player2_hand_space
	else:
		local_hand = _board.player2_hand
		local_space = _board.player2_hand_space
		opponent_hand = _board.player1_hand
		opponent_space = _board.player1_hand_space

	# On mobile the action panel is full-width at the bottom, so hand can be centered.
	# On desktop, shift hand left to avoid the right-side action panel.
	var hand_center_x: float = 0.5 if _board._is_mobile_layout else 0.35
	var hand_width_pct: float = 0.92 if _board._is_mobile_layout else 0.95
	# Cap mobile hand width so cards don't cover action buttons
	const MOBILE_MAX_HAND_WIDTH := 700.0
	var mobile_hand_expand := 120.0 # Smaller expand offset on mobile to avoid obscuring board

	# On mobile, center hands on the viewport (scene) center.
	var viewport_center_x := get_viewport().get_visible_rect().size.x / 2.0

	# Local player hand: visible, centered in hand space
	if local_space and local_hand:
		var rect := local_space.get_global_rect()
		var expand_offset := mobile_hand_expand if _board._is_mobile_layout else _board.HAND_EXPAND_OFFSET
		var y_offset := -expand_offset if _board._hand_expanded else 0.0
		var center_x := viewport_center_x if _board._is_mobile_layout else rect.position.x + rect.size.x * hand_center_x
		# Cards are positioned by top-left corner, so the visual center of the
		# arc is shifted right by half a card width. Compensate on mobile.
		if _board._is_mobile_layout and not local_hand.managed_cards.is_empty():
			var c: Control = local_hand.managed_cards[0]
			center_x -= c.size.x * c.scale.x / 2.0
		local_hand.global_position = Vector2(center_x, rect.position.y + rect.size.y / 2.0 + y_offset)
		var width := rect.size.x * hand_width_pct
		if _board._is_mobile_layout:
			width = minf(width, MOBILE_MAX_HAND_WIDTH)
		local_hand.max_width = width
		local_hand.arrange_cards(false)

		# Position local hand button stack at the bottom, left of the max-width hand edge
		if _board._is_mobile_layout and not local_hand.managed_cards.is_empty():
			var hand_stack := _board.get_node("HandButtonStack") as HBoxContainer
			var stack_w := 150.0
			var stack_h := 60.0
			var cards_left: float = center_x - width / 2.0
			hand_stack.anchor_left = 0.0
			hand_stack.anchor_right = 0.0
			hand_stack.anchor_top = 1.0
			hand_stack.anchor_bottom = 1.0
			var min_left := maxf(20.0, _board._mobile._safe_left + 4.0)
			hand_stack.offset_left = maxf(min_left, cards_left - stack_w)
			hand_stack.offset_right = hand_stack.offset_left + stack_w
			var bot_pad := maxf(20.0, _board._mobile._safe_bottom + 4.0)
			hand_stack.offset_top = - (stack_h + bot_pad - 4.0)
			hand_stack.offset_bottom = - bot_pad

			# Position board view toggle directly above the hand stack
			if _board._mobile._mobile_view_toggle_btn:
				var view_gap := 16.0
				var view_w := 55.0
				var view_h := 60.0
				_board._mobile._mobile_view_toggle_btn.offset_left = hand_stack.offset_left
				_board._mobile._mobile_view_toggle_btn.offset_right = hand_stack.offset_left + view_w
				_board._mobile._mobile_view_toggle_btn.offset_bottom = hand_stack.offset_top - view_gap
				_board._mobile._mobile_view_toggle_btn.offset_top = _board._mobile._mobile_view_toggle_btn.offset_bottom - view_h

	# Opponent hand: mostly off-screen at top edge
	if opponent_space and opponent_hand:
		var rect := opponent_space.get_global_rect()
		var center_x := viewport_center_x if _board._is_mobile_layout else rect.position.x + rect.size.x * hand_center_x
		if _board._is_mobile_layout and not opponent_hand.managed_cards.is_empty():
			var c: Control = opponent_hand.managed_cards[0]
			center_x -= c.size.x * c.scale.x / 2.0
		var opp_base_y := rect.position.y - _board.OPPONENT_HAND_EXPAND_OFFSET
		var opp_y_offset := _board.OPPONENT_HAND_EXPAND_OFFSET if _board._opponent_hand_expanded else 0.0
		opponent_hand.global_position = Vector2(center_x, opp_base_y + opp_y_offset)
		var width := rect.size.x * hand_width_pct
		if _board._is_mobile_layout:
			width = minf(width, MOBILE_MAX_HAND_WIDTH)
		opponent_hand.max_width = width
		opponent_hand.arrange_cards(false)

	# Position opponent hand button stack at top of screen, left of the max-width hand edge
	if _board._is_mobile_layout and opponent_hand and not opponent_hand.managed_cards.is_empty():
		var opp_stack := _board.get_node("OpponentHandButtonStack") as HBoxContainer
		var stack_w := 150.0
		var stack_h := 60.0
		var opp_width: float = opponent_hand.max_width
		var opp_center_x := opponent_hand.global_position.x
		var cards_left: float = opp_center_x - opp_width / 2.0
		opp_stack.anchor_left = 0.0
		opp_stack.anchor_right = 0.0
		opp_stack.anchor_top = 0.0
		opp_stack.anchor_bottom = 0.0
		var opp_min_left := maxf(20.0, _board._mobile._safe_left + 4.0)
		opp_stack.offset_left = maxf(opp_min_left, cards_left - stack_w)
		opp_stack.offset_right = opp_stack.offset_left + stack_w
		# Use generous minimum top padding to avoid iOS screen-edge gesture zone
		# and to sit below the phase label
		var top_pad := maxf(40.0, _board._mobile._safe_top + 24.0)
		opp_stack.offset_top = top_pad
		opp_stack.offset_bottom = top_pad + stack_h

		# Bot visibility button below opponent hand stack
		if _board._bot_visibility_button:
			_board._bot_visibility_button.anchor_left = 0.0
			_board._bot_visibility_button.anchor_right = 0.0
			_board._bot_visibility_button.anchor_top = 0.0
			_board._bot_visibility_button.anchor_bottom = 0.0
			_board._bot_visibility_button.offset_left = opp_stack.offset_left
			_board._bot_visibility_button.offset_right = opp_stack.offset_right
			_board._bot_visibility_button.offset_top = top_pad + stack_h + 4.0
			_board._bot_visibility_button.offset_bottom = top_pad + stack_h + 4.0 + 36.0


func _fit_button_text(btn: Button, base_size: int = 18, min_size: int = 10) -> void:
	if not _board._is_mobile_layout:
		return
	btn.clip_text = true
	var font := btn.get_theme_font("font")
	# Account for Godot's internal button padding (~16px) plus corner radius inset
	var available_w := btn.size.x - 32.0
	var font_size := base_size
	while font_size > min_size:
		var text_w := font.get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if text_w <= available_w:
			break
		font_size -= 1
	btn.add_theme_font_size_override("font_size", font_size)


## Apply a tab/handle style to a button on a screen edge.
## edge_side: "left" = flush left edge, rounded right; "right" = flush right edge, rounded left.


func _apply_desktop_hand_button_stacks() -> void:
	# Stack buttons vertically on desktop between the hand and action panel.
	# Hide the HBoxContainers and reparent buttons to GameBoard for free positioning.
	_board.get_node("HandButtonStack").visible = false
	_board.get_node("OpponentHandButtonStack").visible = false

	var btn_w := 55.0
	var btn_h := 32.0
	var gap := 2.0
	var right_margin := 300.0 # Action panel left edge is at -270

	# Reparent to GameBoard so HBoxContainer can't override layout
	_board.hand_toggle_button.reparent(_board)
	_board.sort_hand_button.reparent(_board)
	_board.opponent_hand_toggle_button.reparent(_board)
	_board.opponent_sort_hand_button.reparent(_board)

	# Reset minimum sizes from .tscn so offset-based sizing works
	for btn: Button in [_board.hand_toggle_button, _board.sort_hand_button,
			_board.opponent_hand_toggle_button, _board.opponent_sort_hand_button]:
		btn.custom_minimum_size = Vector2.ZERO

	# Local player — bottom-right, stacked vertically
	for btn: Button in [_board.hand_toggle_button, _board.sort_hand_button]:
		btn.anchor_left = 1.0
		btn.anchor_right = 1.0
		btn.anchor_top = 1.0
		btn.anchor_bottom = 1.0
	_board.hand_toggle_button.offset_left = - (right_margin + btn_w)
	_board.hand_toggle_button.offset_right = - right_margin
	_board.hand_toggle_button.offset_bottom = - (btn_h + gap + 10.0)
	_board.hand_toggle_button.offset_top = _board.hand_toggle_button.offset_bottom - btn_h
	_board.sort_hand_button.offset_left = - (right_margin + btn_w)
	_board.sort_hand_button.offset_right = - right_margin
	_board.sort_hand_button.offset_bottom = -10.0
	_board.sort_hand_button.offset_top = _board.sort_hand_button.offset_bottom - btn_h

	# Opponent — top-right, stacked vertically (hidden in multiplayer)
	for btn: Button in [_board.opponent_hand_toggle_button, _board.opponent_sort_hand_button]:
		btn.visible = not _board.is_multiplayer_game
		btn.anchor_left = 1.0
		btn.anchor_right = 1.0
		btn.anchor_top = 0.0
		btn.anchor_bottom = 0.0
	_board.opponent_hand_toggle_button.offset_left = - (right_margin + btn_w)
	_board.opponent_hand_toggle_button.offset_right = - right_margin
	_board.opponent_hand_toggle_button.offset_top = 10.0
	_board.opponent_hand_toggle_button.offset_bottom = 10.0 + btn_h
	_board.opponent_sort_hand_button.offset_left = - (right_margin + btn_w)
	_board.opponent_sort_hand_button.offset_right = - right_margin
	_board.opponent_sort_hand_button.offset_top = 10.0 + btn_h + gap
	_board.opponent_sort_hand_button.offset_bottom = 10.0 + btn_h * 2 + gap

	# Bot visibility button below sort button
	if _board._bot_visibility_button:
		_board._bot_visibility_button.anchor_left = 1.0
		_board._bot_visibility_button.anchor_right = 1.0
		_board._bot_visibility_button.anchor_top = 0.0
		_board._bot_visibility_button.anchor_bottom = 0.0
		var bot_top := 10.0 + btn_h * 2 + gap * 2
		_board._bot_visibility_button.offset_left = - (right_margin + btn_w)
		_board._bot_visibility_button.offset_right = - right_margin
		_board._bot_visibility_button.offset_top = bot_top
		_board._bot_visibility_button.offset_bottom = bot_top + btn_h
		_board._bot_visibility_button.custom_minimum_size = Vector2.ZERO


# --- State access helpers (work for both host and client) ---


func _update_hand_visibility(_active_player_id: int) -> void:
	if _board.is_multiplayer_game:
		# Multiplayer: local player always face-up, opponent always face-down
		if _board.player1_board:
			_board.player1_board.set_hand_face_down(_board.local_player_id != 0)
		if _board.player2_board:
			_board.player2_board.set_hand_face_down(_board.local_player_id != 1)
	elif _board.is_bot_game:
		# Bot mode: P1 (human) face-up, P2 (bot) respects visibility toggle
		if _board.player1_board:
			_board.player1_board.set_hand_face_down(false)
		if _board.player2_board:
			_board.player2_board.set_hand_face_down(not _board._bot_cards_visible)
	else:
		# Solo: both hands always face-up
		if _board.player1_board:
			_board.player1_board.set_hand_face_down(false)
		if _board.player2_board:
			_board.player2_board.set_hand_face_down(false)


## Translate player.hand indices to managed_cards indices by matching card IDs


## Find a card's index in player.hand by its unique ID


# --- Drag-to-zone ---


# --- Deck search UI ---

# --- FAB (Floating Action Button) ---


# --- FAB Icon Drawing ---


func _temporarily_collapse_hand() -> void:
	_board._hand.temporarily_collapse_hand()


func _restore_expanded_hand() -> void:
	_board._hand.restore_expanded_hand()


func _temporarily_collapse_opponent_hand() -> void:
	_board._hand.temporarily_collapse_opponent_hand()


func _restore_expanded_opponent_hand() -> void:
	_board._hand.restore_expanded_opponent_hand()


## Router view-board hook: stash the overlay so ShowCards can re-show it.
