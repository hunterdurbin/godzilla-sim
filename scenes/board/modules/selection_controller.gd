class_name SelectionController
extends Node

## Player action-selection concern for the game board: the action buttons,
## click-based card/zone selection, drag-to-zone with snap preview, the pass
## confirmation, and the inline effect prompts that select from the hand or
## board (hand discard, hand card selection, zone target, strategy target,
## choice buttons).
##
## Function bodies moved verbatim from game_board.gd; the "board bridge"
## section below resolves the identifiers they reference. The bridge thins
## out as later steps move the remaining owners (mobile FAB, confirmation).
##
## Effect-prompt request signals bind on session_started (idempotent,
## rematch-safe). The board's _input/_process keep their exact event
## ordering and delegate into this controller.

var _board: Node
var _session: GameSession

# --- Selection state (moved wholesale — one state machine) ---
var pending_action: CardEnums.ActionType = CardEnums.ActionType.PASS
var waiting_for_card_select: bool = false
var waiting_for_zone_select: bool = false
var selected_card_id: String = ""
var _selected_card_data: Dictionary = {} # Card data dict for the selected card
var _confirming_pass: bool = false
var _zone_select_valid: Array[int] = []
var _snap_preview_slot = null # Slot or Control currently being snap-previewed
var _highlighted_card: Control = null # Card with selection highlight border

# Drag-to-zone state
var _drag_card: Control = null
var _drag_valid_zones: Array[int] = []
var _drag_action: CardEnums.ActionType = CardEnums.ActionType.PASS
var _drag_can_rage: bool = false
var _drag_can_invade: bool = false

# Hand discard selection state
var _discard_selecting: bool = false
var _discard_player_id: int = -1
var _discard_count: int = 0
var _discard_selected_cards: Array[Control] = []

# Hand card selection state (single-select for effects like ESD02-004)
var _hand_card_selecting: bool = false
var _hand_card_player_id: int = -1
var _hand_card_allow_skip: bool = false

# Zone target selection state (for effects that let the player pick a zone)
var _zone_target_selecting: bool = false
var _zone_target_player_id: int = -1 # Who is choosing
var _zone_target_board_pid: int = -1 # Whose board the zones are on
var _zone_target_valid_zones: Array[int] = []
var _zone_target_allow_skip: bool = false

# Strategy target selection state
var _strategy_target_selecting: bool = false
var _strategy_target_player_id: int = -1
var _strategy_target_board_pid: int = -1
var _strategy_target_valid_indices: Array[int] = []

# Choice button selection state
var _choice_selecting: bool = false
var _choice_player_id: int = -1
var _choice_buttons: Array[Button] = []
var _choice_container: VBoxContainer = null
var _choice_panel: PanelContainer = null # Mobile wrapper panel

# --- Board bridge: widgets ---
var action_panel: Control
var action_prompt_panel: PanelContainer
var card_select_prompt: Label
var btn_play_battle: Button
var btn_play_strategy: Button
var btn_gain_rage: Button
var btn_play_monster: Button
var btn_invade: Button
var btn_end_main: Button
var btn_cancel: Button
var btn_confirm: Button
var player1_board: Control
var player2_board: Control
var player1_hand: Node2D
var player2_hand: Node2D

func _ready() -> void:
	_board = get_parent()
	var session_node := _board.get_node_or_null("GameSession")
	if session_node:
		_session = session_node
		_session.session_started.connect(_bind_session)


## Resolve widget refs and wire the action buttons + hand drag signals.
## Called from the board's _ready.
func setup() -> void:
	action_panel = _board.action_panel
	action_prompt_panel = _board.action_prompt_panel
	card_select_prompt = _board.card_select_prompt
	btn_play_battle = _board.btn_play_battle
	btn_play_strategy = _board.btn_play_strategy
	btn_gain_rage = _board.btn_gain_rage
	btn_play_monster = _board.btn_play_monster
	btn_invade = _board.btn_invade
	btn_end_main = _board.btn_end_main
	btn_cancel = _board.btn_cancel
	btn_confirm = _board.btn_confirm
	player1_board = _board.player1_board
	player2_board = _board.player2_board
	player1_hand = _board.player1_hand
	player2_hand = _board.player2_hand

	btn_play_battle.pressed.connect(_on_play_battle_pressed)
	btn_play_strategy.pressed.connect(_on_play_strategy_pressed)
	btn_gain_rage.pressed.connect(_on_gain_rage_pressed)
	btn_play_monster.pressed.connect(_on_play_monster_pressed)
	btn_invade.pressed.connect(_on_invade_pressed)
	btn_end_main.pressed.connect(_on_end_main_pressed)
	btn_cancel.pressed.connect(_on_cancel_pressed)
	btn_confirm.pressed.connect(_on_confirm_pressed)
	player1_hand.hand_card_drag_started.connect(_on_hand_drag_started)
	player1_hand.hand_card_drag_ended.connect(_on_hand_drag_ended)
	player2_hand.hand_card_drag_started.connect(_on_hand_drag_started)
	player2_hand.hand_card_drag_ended.connect(_on_hand_drag_ended)


func _bind_session() -> void:
	var tm: TurnManager = _session.turn_manager
	if tm == null:
		return # Client peer: prompts arrive via the MultiplayerSync forwarders
	var eh: EffectHandler = tm.action_handler.effect_handler
	_connect_once(eh.hand_discard_requested, _on_hand_discard_requested)
	_connect_once(eh.hand_card_selection_requested, _on_hand_card_selection_requested)
	_connect_once(eh.zone_target_requested, _on_zone_target_requested)
	_connect_once(eh.strategy_target_requested, _on_strategy_target_requested)
	_connect_once(eh.choice_requested, _on_choice_requested)


func _connect_once(sig: Signal, callback: Callable) -> void:
	if not sig.is_connected(callback):
		sig.connect(callback)


## Reset all selection state for a rematch (called from the board's
## rematch reset).
func reset_for_rematch() -> void:
	_confirming_pass = false
	_discard_selecting = false
	_discard_player_id = -1
	_discard_count = 0
	_discard_selected_cards.clear()
	_hand_card_selecting = false
	_hand_card_player_id = -1
	_hand_card_allow_skip = false
	_zone_target_selecting = false
	_zone_target_player_id = -1
	_zone_target_board_pid = -1
	_zone_target_valid_zones.clear()
	_zone_target_allow_skip = false
	_strategy_target_selecting = false
	_strategy_target_player_id = -1
	_strategy_target_board_pid = -1
	_strategy_target_valid_indices.clear()
	_choice_selecting = false
	_choice_player_id = -1
	waiting_for_card_select = false
	waiting_for_zone_select = false
	selected_card_id = ""
	_selected_card_data = {}
	_zone_select_valid.clear()
	_drag_card = null
	_drag_valid_zones.clear()
	_drag_action = CardEnums.ActionType.PASS
	_drag_can_rage = false
	_drag_can_invade = false
	pending_action = CardEnums.ActionType.PASS


## Per-frame drag snap preview (called from the board's _process so the
## reconnect-overlay early-return ordering is preserved).
func process_drag() -> void:
	if not _drag_card or not _drag_card.is_dragging:
		if _snap_preview_slot:
			_end_snap_preview()
		return
	_update_snap_preview()


# --- Board bridge: state owned elsewhere ---
var turn_manager: TurnManager:
	get: return _board.turn_manager
var is_multiplayer_game: bool:
	get: return _board.is_multiplayer_game
var is_bot_game: bool:
	get: return _board.is_bot_game
var local_player_id: int:
	get: return _board.local_player_id
var bot_player: BotPlayer:
	get: return _board.bot_player
var _client_playable: Dictionary:
	get: return _board._client_playable
	set(v): _board._client_playable = v
var _pending_interaction: Dictionary:
	get: return _board._pending_interaction
	set(v): _board._pending_interaction = v
var _action_pending: bool:
	get: return _board._action_pending
	set(v): _board._action_pending = v
var _is_mobile_layout: bool:
	get: return _board._is_mobile_layout
var _sync: MultiplayerSync:
	get: return _board._sync
var _awaiting_confirmation: bool:
	get: return _board._awaiting_confirmation
	set(v): _board._awaiting_confirmation = v
var _player_settings: Array[Dictionary]:
	get: return _board._player_settings
var _fab_container: Control:
	get: return _board._fab_container
var _fab_action_btns: Array[Button]:
	get: return _board._fab_action_btns

# --- Board bridge: helpers still owned by the board ---
func _board_zone_slot_clicked_cb() -> Callable:
	return Callable(_board, "_on_zone_slot_clicked")

func _submit_action(action: CardEnums.ActionType, params: Dictionary = {}) -> void:
	_board._submit_action(action, params)

func _get_current_pid() -> int:
	return _board._get_current_pid()

func _get_player_state(pid: int) -> PlayerState:
	return _board._get_player_state(pid)

func _get_current_player() -> PlayerState:
	return _board._get_current_player()

func _flush_broadcast() -> void:
	_board._flush_broadcast()

func _resolve_translated_text(text: String) -> String:
	return _board._resolve_translated_text(text)

func _update_hand_visibility(active_player_id: int) -> void:
	_board._update_hand_visibility(active_player_id)

func _temporarily_collapse_hand() -> void:
	_board._hand.temporarily_collapse_hand()

func _restore_expanded_hand() -> void:
	_board._hand.restore_expanded_hand()

func _temporarily_collapse_opponent_hand() -> void:
	_board._hand.temporarily_collapse_opponent_hand()

func _restore_expanded_opponent_hand() -> void:
	_board._hand.restore_expanded_opponent_hand()

func _play_action_required_if_not_turn_player(player_id: int) -> void:
	_board._play_action_required_if_not_turn_player(player_id)

func _on_log_message(message) -> void:
	_board._on_log_message(message)

func _set_action_buttons_visible(vis: bool) -> void:
	_board._set_action_buttons_visible(vis)


# --- Moved bodies (verbatim from game_board.gd) ---

func _on_play_battle_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		var state := turn_manager.game_state
		playable = turn_manager.rules_engine.get_playable_battle_cards(state.get_current_player(), state.get_opponent_of_current())
	else:
		playable.assign(_client_playable.get("battle_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.PLAY_BATTLE
	_enter_card_selection(tr("STR_GB_SELECT_BATTLE_TO_PLAY"), playable)


func _on_play_strategy_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		playable = turn_manager.rules_engine.get_playable_strategy_cards(turn_manager.game_state.get_current_player())
	else:
		playable.assign(_client_playable.get("strategy_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.PLAY_STRATEGY
	_enter_card_selection(tr("STR_GB_SELECT_STRATEGY_TO_ACTIVATE"), playable)


func _on_gain_rage_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		playable = turn_manager.rules_engine.get_monster_cards_for_rage(turn_manager.game_state.get_current_player())
	else:
		playable.assign(_client_playable.get("rage_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.GAIN_RAGE
	_enter_card_selection(tr("STR_GB_SELECT_RAGE_CARD"), playable)


func _on_play_monster_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		playable = turn_manager.rules_engine.get_playable_monsters(turn_manager.game_state.get_current_player())
	else:
		playable.assign(_client_playable.get("monster_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.PLAY_MONSTER
	_enter_card_selection(tr("STR_GB_SELECT_MONSTER_TO_PLAY"), playable)


func _on_invade_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		playable = turn_manager.rules_engine.get_discardable_cards_for_invade(turn_manager.game_state.get_current_player(), turn_manager.game_state.get_opponent_of_current())
	else:
		playable.assign(_client_playable.get("invade_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.INVADE
	_enter_card_selection(tr("STR_GB_SELECT_INVASION_CARD"), playable)


func _on_end_main_pressed() -> void:
	if _player_settings[_get_current_pid()].get("confirm_main_phase_pass", false):
		_enter_pass_confirmation()
		return
	_clear_card_highlight()
	_cancel_selection()
	_submit_action(CardEnums.ActionType.PASS)


func _on_confirm_pressed() -> void:
	if _awaiting_confirmation:
		return
	if _confirming_pass:
		_confirming_pass = false
		_clear_card_highlight()
		_cancel_selection()
		_submit_action(CardEnums.ActionType.PASS)
		return
	if _hand_card_selecting and _hand_card_allow_skip:
		_skip_hand_card_selection()
		return
	if _zone_target_selecting and _zone_target_allow_skip:
		_skip_zone_target()
		return
	if _discard_selecting and _discard_selected_cards.size() == _discard_count:
		_confirm_hand_discard()
		return


func _on_cancel_pressed() -> void:
	if _confirming_pass:
		_cancel_pass_confirmation()
		return
	if waiting_for_card_select or waiting_for_zone_select:
		_clear_card_highlight()
		_cancel_selection()
		if turn_manager:
			_update_action_buttons(turn_manager.rules_engine.get_valid_actions(turn_manager.game_state))
		else:
			_update_action_buttons(_client_playable.get("valid_actions", []))
		return


func _enter_pass_confirmation() -> void:
	_confirming_pass = true
	_disable_all_buttons()
	action_prompt_panel.visible = true
	card_select_prompt.text = tr("STR_GB_END_MAIN_QUESTION")
	btn_confirm.text = tr("STR_GB_CONFIRM")
	btn_confirm.disabled = false
	btn_cancel.text = tr("STR_GB_CANCEL")
	btn_cancel.disabled = false


func _cancel_pass_confirmation() -> void:
	_confirming_pass = false
	action_prompt_panel.visible = false
	btn_confirm.disabled = true
	btn_cancel.disabled = true
	if turn_manager:
		_update_action_buttons(turn_manager.rules_engine.get_valid_actions(turn_manager.game_state))
	else:
		_update_action_buttons(_client_playable.get("valid_actions", []))


func _enter_card_selection(prompt_text: String, valid_indices: Array[int]) -> void:
	waiting_for_card_select = true
	card_select_prompt.text = _resolve_translated_text(prompt_text)
	action_prompt_panel.visible = true
	_disable_all_buttons()
	btn_cancel.text = tr("STR_GB_CANCEL")
	btn_cancel.disabled = false

	var board := _get_active_player_board()
	if board and board.hand_manager:
		var visual_indices := _hand_indices_to_visual(valid_indices, board)
		board.hand_manager.enter_selection_mode(visual_indices)
		if not board.hand_manager.card_selected.is_connected(_on_hand_card_selected):
			board.hand_manager.card_selected.connect(_on_hand_card_selected)


func _on_hand_card_selected(card: Control, _visual_index: int) -> void:
	if not waiting_for_card_select:
		return

	_selected_card_data = card.card_data if "card_data" in card else {}
	selected_card_id = _selected_card_data.get("id", "")
	if selected_card_id.is_empty():
		return

	_set_card_highlight(card)

	match pending_action:
		CardEnums.ActionType.PLAY_BATTLE:
			_enter_zone_selection()
		CardEnums.ActionType.PLAY_STRATEGY:
			var idx := _find_hand_index_by_id(selected_card_id)
			_cancel_selection()
			if idx >= 0:
				_submit_action(CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": idx})
		CardEnums.ActionType.GAIN_RAGE:
			var idx := _find_hand_index_by_id(selected_card_id)
			_cancel_selection()
			if idx >= 0:
				_submit_action(CardEnums.ActionType.GAIN_RAGE, {"hand_index": idx})
		CardEnums.ActionType.PLAY_MONSTER:
			var idx := _find_hand_index_by_id(selected_card_id)
			_cancel_selection()
			if idx >= 0:
				_submit_action(CardEnums.ActionType.PLAY_MONSTER, {"hand_index": idx})
		CardEnums.ActionType.INVADE:
			var idx := _find_hand_index_by_id(selected_card_id)
			_cancel_selection()
			if idx >= 0:
				_submit_action(CardEnums.ActionType.INVADE, {"hand_index": idx})


func _enter_zone_selection() -> void:
	waiting_for_card_select = false
	waiting_for_zone_select = true
	card_select_prompt.text = tr("STR_GB_SELECT_ZONE")
	var active_pid := _get_current_pid()
	if not is_multiplayer_game and active_pid != local_player_id:
		_temporarily_collapse_opponent_hand()
	else:
		_temporarily_collapse_hand()

	var valid_zones: Array[int] = []
	if turn_manager:
		var state := turn_manager.game_state
		var player := state.get_current_player()
		var opponent := state.get_opponent_of_current()
		if not _selected_card_data.is_empty():
			valid_zones = turn_manager.rules_engine.get_valid_zones_for_card(_selected_card_data, player, opponent)
		else:
			valid_zones = turn_manager.rules_engine.get_valid_zones_for_battle_card(player, opponent)
	else:
		var card_id: String = _selected_card_data.get("id", "")
		var zones_data = _client_playable.get("battle_zones", {})
		if zones_data is Dictionary:
			valid_zones.assign(zones_data.get(card_id, []))
		else:
			valid_zones.assign(zones_data)

	_zone_select_valid = valid_zones

	var board := _get_active_player_board()
	if board:
		board.hand_manager.exit_selection_mode()
		board.highlight_valid_zones(valid_zones)
		for i in range(board.zone_slots.size()):
			var slot: Slot = board.zone_slots[i]
			if i in valid_zones:
				slot.in_selection_mode = true
				slot.accept_cards = true
				if not slot.card_placed.is_connected(_board_zone_slot_clicked_cb()):
					slot.card_placed.connect(_board_zone_slot_clicked_cb().bind(i))
				if not slot.hover_started.is_connected(_on_zone_hover_clicked):
					slot.hover_started.connect(_on_zone_hover_clicked.bind(i))


func _on_zone_hover_clicked(_zone_index: int) -> void:
	if not waiting_for_zone_select:
		return
	pass


func _update_snap_preview() -> void:
	var board := _get_active_player_board()
	if not board:
		return

	var mouse_pos: Vector2 = _board.get_global_mouse_position()
	var hovered_slot = null # Slot or Control

	# Check zone slots
	for i in _drag_valid_zones:
		if i < 0 or i >= board.zone_slots.size():
			continue
		var slot: Slot = board.zone_slots[i]
		if slot and Rect2(slot.global_position, slot.size).has_point(mouse_pos):
			hovered_slot = slot
			break

	# Check strategy slots
	if not hovered_slot and _drag_action == CardEnums.ActionType.PLAY_STRATEGY:
		for slot in board.strategy_slots:
			if slot and not slot.has_card() and Rect2(slot.global_position, slot.size).has_point(mouse_pos):
				hovered_slot = slot
				break

	# Check rage zone
	if not hovered_slot and _drag_can_rage and board.rage_display:
		if Rect2(board.rage_display.global_position, board.rage_display.size).has_point(mouse_pos):
			hovered_slot = board.rage_display

	# Check discard zone
	if not hovered_slot and _drag_can_invade and board.discard_display:
		if Rect2(board.discard_display.global_position, board.discard_display.size).has_point(mouse_pos):
			hovered_slot = board.discard_display

	if hovered_slot == _snap_preview_slot:
		return # No change

	if _snap_preview_slot and hovered_slot != _snap_preview_slot:
		_end_snap_preview()

	if hovered_slot:
		_start_snap_preview(hovered_slot)


func _start_snap_preview(target) -> void:
	_snap_preview_slot = target

	# Compute snap position and scale based on target type
	var target_rect: Rect2
	if target is Slot:
		# Use the slot's content rect (card aspect ratio area) for precise positioning
		var content_rect: Rect2 = target._content_rect
		target_rect = Rect2(target.global_position + content_rect.position, content_rect.size)
	else:
		# For non-slot targets (rage/discard display), use the full control rect
		target_rect = Rect2(target.global_position, target.size)

	# Calculate scale to fit card in the target area (maintain aspect ratio)
	var card_size: Vector2 = _drag_card.size # Base card size (150x210)
	var scale_x := target_rect.size.x / card_size.x
	var scale_y := target_rect.size.y / card_size.y
	var fit_scale := minf(scale_x, scale_y)
	var target_scale := Vector2(fit_scale, fit_scale)

	# Position: center the scaled card within the target rect
	var scaled_size := card_size * fit_scale
	var target_pos := target_rect.position + (target_rect.size - scaled_size) / 2.0

	_drag_card.start_snap_preview(target_pos, target_scale)


func _end_snap_preview() -> void:
	_snap_preview_slot = null
	if _drag_card and _drag_card.is_snap_previewing:
		_drag_card.end_snap_preview()


func _cancel_selection() -> void:
	waiting_for_card_select = false
	waiting_for_zone_select = false
	selected_card_id = ""
	_selected_card_data = {}
	_zone_select_valid = []
	action_prompt_panel.visible = false
	btn_confirm.disabled = true
	btn_cancel.disabled = true
	_restore_expanded_hand()
	_restore_expanded_opponent_hand()

	for board in [player1_board, player2_board]:
		if board and board.hand_manager:
			board.hand_manager.exit_selection_mode()
			if board.hand_manager.card_selected.is_connected(_on_hand_card_selected):
				board.hand_manager.card_selected.disconnect(_on_hand_card_selected)
		if board:
			board.clear_highlights()
			for slot in board.zone_slots:
				slot.in_selection_mode = false
				if slot.card_placed.is_connected(_board_zone_slot_clicked_cb()):
					slot.card_placed.disconnect(_board_zone_slot_clicked_cb())
				if slot.hover_started.is_connected(_on_zone_hover_clicked):
					slot.hover_started.disconnect(_on_zone_hover_clicked)


func _update_action_buttons(valid_actions: Array) -> void:
	_confirming_pass = false
	btn_invade.text = tr("STR_GB_INVADE")
	btn_play_battle.disabled = CardEnums.ActionType.PLAY_BATTLE not in valid_actions
	btn_play_strategy.disabled = CardEnums.ActionType.PLAY_STRATEGY not in valid_actions
	btn_gain_rage.disabled = CardEnums.ActionType.GAIN_RAGE not in valid_actions
	btn_play_monster.disabled = CardEnums.ActionType.PLAY_MONSTER not in valid_actions
	btn_invade.disabled = CardEnums.ActionType.INVADE not in valid_actions
	btn_end_main.disabled = false
	btn_end_main.visible = true
	btn_confirm.disabled = true
	btn_cancel.disabled = true
	action_prompt_panel.visible = false
	# Redraw FAB icons to reflect enabled/disabled state
	if _fab_container:
		for btn: Button in _fab_action_btns:
			btn.queue_redraw()


func _disable_all_buttons() -> void:
	btn_play_battle.disabled = true
	btn_play_strategy.disabled = true
	btn_gain_rage.disabled = true
	btn_play_monster.disabled = true
	btn_invade.disabled = true
	btn_end_main.disabled = true
	btn_confirm.disabled = true
	btn_cancel.disabled = true
	if _fab_container:
		for btn: Button in _fab_action_btns:
			btn.queue_redraw()


func _get_active_player_board() -> Control:
	var active_id: int = _get_current_pid()
	if active_id == 0:
		return player1_board
	else:
		return player2_board


func _hand_indices_to_visual(hand_indices: Array[int], board: Control, player_id: int = -1) -> Array[int]:
	var player := _get_player_state(player_id) if player_id >= 0 else _get_current_player()
	var visual: Array[int] = []
	var cards: Array[Control] = board.hand_manager.get_cards()
	for hand_idx in hand_indices:
		if hand_idx >= player.hand.size():
			continue
		var card_id: String = player.hand[hand_idx].get("id", "")
		for j in range(cards.size()):
			if "card_data" in cards[j] and cards[j].card_data.get("id") == card_id:
				visual.append(j)
				break
	return visual


func _find_hand_index_by_id(card_id: String) -> int:
	var player := _get_current_player()
	for i in range(player.hand.size()):
		if player.hand[i].get("id") == card_id:
			return i
	return -1


func _on_hand_drag_started(card: Control) -> void:
	if _action_pending:
		return
	if waiting_for_card_select or waiting_for_zone_select:
		return
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var card_data: Dictionary = card.card_data if "card_data" in card else {}
	if card_data.is_empty():
		return

	var player := _get_current_player()
	var board := _get_active_player_board()
	if not board:
		return

	if board.hand_manager != card.get_parent():
		return

	var card_type = card_data.get("card_type", -1)
	_drag_card = card
	_drag_valid_zones = []
	_drag_action = CardEnums.ActionType.PASS
	_drag_can_rage = false
	_drag_can_invade = false
	_snap_preview_slot = null

	if card_type == CardEnums.CardType.BATTLE:
		var card_id: String = card_data.get("id", "")
		var hand_idx := _find_hand_index_by_id(card_id)
		if hand_idx >= 0:
			var playable_battle: Array[int] = []
			var valid_zones: Array[int] = []
			if turn_manager:
				var opponent := turn_manager.game_state.get_opponent_of_current()
				playable_battle = turn_manager.rules_engine.get_playable_battle_cards(player, opponent)
				valid_zones = turn_manager.rules_engine.get_valid_zones_for_card(card_data, player, opponent)
			else:
				playable_battle.assign(_client_playable.get("battle_cards", []))
				var zones_data = _client_playable.get("battle_zones", {})
				if zones_data is Dictionary:
					valid_zones.assign(zones_data.get(card_id, []))
				else:
					valid_zones.assign(zones_data)
			if hand_idx in playable_battle:
				_drag_valid_zones = valid_zones
				_drag_action = CardEnums.ActionType.PLAY_BATTLE

	elif card_type == CardEnums.CardType.MONSTER:
		var card_id: String = card_data.get("id", "")
		var hand_idx := _find_hand_index_by_id(card_id)
		if hand_idx >= 0:
			# Check if this monster can be played onto the current monster
			var playable_monsters: Array[int] = []
			if turn_manager:
				playable_monsters = turn_manager.rules_engine.get_playable_monsters(player)
			else:
				playable_monsters.assign(_client_playable.get("monster_cards", []))
			if hand_idx in playable_monsters:
				var monster_zone_idx: int = player.monster_zone - 1
				if monster_zone_idx >= 0 and monster_zone_idx < 8:
					_drag_valid_zones = [monster_zone_idx]
					_drag_action = CardEnums.ActionType.PLAY_MONSTER
			# Any monster card can also be discarded for rage
			var rage_cards: Array[int] = []
			if turn_manager:
				rage_cards = turn_manager.rules_engine.get_monster_cards_for_rage(player)
			else:
				rage_cards.assign(_client_playable.get("rage_cards", []))
			if hand_idx in rage_cards:
				_drag_can_rage = true

	elif card_type == CardEnums.CardType.STRATEGY:
		var card_id: String = card_data.get("id", "")
		var hand_idx := _find_hand_index_by_id(card_id)
		if hand_idx >= 0:
			var playable_strategy: Array[int] = []
			if turn_manager:
				playable_strategy = turn_manager.rules_engine.get_playable_strategy_cards(player)
			else:
				playable_strategy.assign(_client_playable.get("strategy_cards", []))
			if hand_idx in playable_strategy:
				_drag_action = CardEnums.ActionType.PLAY_STRATEGY

	# Any card with invasion_icon > 0 can be discarded for invasion
	if card_data.get("invasion_icon", 0) > 0:
		var card_id: String = card_data.get("id", "")
		var hand_idx := _find_hand_index_by_id(card_id)
		if hand_idx >= 0:
			var invade_cards: Array[int] = []
			if turn_manager:
				invade_cards = turn_manager.rules_engine.get_discardable_cards_for_invade(player, turn_manager.game_state.get_opponent_of_current())
			else:
				invade_cards.assign(_client_playable.get("invade_cards", []))
			if hand_idx in invade_cards:
				_drag_can_invade = true

	if not _drag_valid_zones.is_empty():
		board.highlight_valid_zones(_drag_valid_zones)
	if _drag_action == CardEnums.ActionType.PLAY_STRATEGY:
		board.highlight_strategy_zones()
	if _drag_can_rage:
		board.highlight_rage_zone(true)
	if _drag_can_invade:
		board.highlight_discard_zone(true)

	var active_pid := _get_current_pid()
	if not is_multiplayer_game and active_pid != local_player_id:
		_temporarily_collapse_opponent_hand()
	else:
		_temporarily_collapse_hand()


func _on_hand_drag_ended(card: Control) -> void:
	_end_snap_preview()

	var board := _get_active_player_board()

	if board:
		board.clear_highlights()

	var has_drag_target := not _drag_valid_zones.is_empty() or _drag_action == CardEnums.ActionType.PLAY_STRATEGY or _drag_can_rage or _drag_can_invade
	if _drag_card != card or not has_drag_target:
		_drag_card = null
		_drag_valid_zones = []
		_drag_can_rage = false
		_drag_can_invade = false
		_restore_expanded_hand()
		_restore_expanded_opponent_hand()
		return

	var mouse_pos: Vector2 = _board.get_global_mouse_position()
	if board:
		# Check rage zone drop (monster cards discarded for rage)
		if _drag_can_rage and board.rage_display:
			var rage_rect := Rect2(board.rage_display.global_position, board.rage_display.size)
			if rage_rect.has_point(mouse_pos):
				var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
				var hand_idx := _find_hand_index_by_id(card_id)
				if hand_idx >= 0:
					board.hand_manager.drop_handled = true
					_drag_card = null
					_drag_valid_zones = []
					_drag_can_rage = false
					_drag_can_invade = false
					_restore_expanded_hand()
					_restore_expanded_opponent_hand()
					_submit_action(CardEnums.ActionType.GAIN_RAGE, {"hand_index": hand_idx})
					return

		# Check discard zone drop (cards with invasion_icon discarded for invasion)
		if _drag_can_invade and board.discard_display:
			var discard_rect := Rect2(board.discard_display.global_position, board.discard_display.size)
			if discard_rect.has_point(mouse_pos):
				var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
				var hand_idx := _find_hand_index_by_id(card_id)
				if hand_idx >= 0:
					board.hand_manager.drop_handled = true
					_drag_card = null
					_drag_valid_zones = []
					_drag_can_rage = false
					_drag_can_invade = false
					_restore_expanded_hand()
					_restore_expanded_opponent_hand()
					_submit_action(CardEnums.ActionType.INVADE, {"hand_index": hand_idx})
					return

		# Strategy cards target strategy slots (auto-placed, no zone_index needed)
		if _drag_action == CardEnums.ActionType.PLAY_STRATEGY:
			for slot in board.strategy_slots:
				if slot and not slot.has_card():
					var rect := Rect2(slot.global_position, slot.size)
					if rect.has_point(mouse_pos):
						var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
						var hand_idx := _find_hand_index_by_id(card_id)
						if hand_idx >= 0:
							board.hand_manager.drop_handled = true
							_drag_card = null
							_drag_valid_zones = []
							_restore_expanded_hand()
							_restore_expanded_opponent_hand()
							_submit_action(CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": hand_idx})
							return
		else:
			for i in _drag_valid_zones:
				var slot: Slot = board.zone_slots[i]
				var rect := Rect2(slot.global_position, slot.size)
				var is_valid_target: bool = false
				is_valid_target = rect.has_point(mouse_pos)
				if is_valid_target:
					var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
					var hand_idx := _find_hand_index_by_id(card_id)
					if hand_idx >= 0:
						board.hand_manager.drop_handled = true
						card.is_locked_in_zone = true
						_drag_card = null
						_drag_valid_zones = []
						_restore_expanded_hand()
						_restore_expanded_opponent_hand()
						var params := {"hand_index": hand_idx}
						if _drag_action != CardEnums.ActionType.PLAY_MONSTER:
							params["zone_index"] = i
						_submit_action(_drag_action, params)
						return

	_drag_card = null
	_drag_valid_zones = []
	_drag_can_rage = false
	_drag_can_invade = false
	_restore_expanded_hand()
	_restore_expanded_opponent_hand()


func _set_card_highlight(card: Control) -> void:
	_clear_card_highlight()
	if card and card.has_method("set_highlight"):
		card.set_highlight(true)
		_highlighted_card = card


func _clear_card_highlight() -> void:
	if _highlighted_card and is_instance_valid(_highlighted_card) and _highlighted_card.has_method("set_highlight"):
		_highlighted_card.set_highlight(false)
	_highlighted_card = null


func _on_hand_discard_requested(player_id: int, discard_count: int) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		_pending_interaction = {"method": "hand_discard", "args": [discard_count]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("hand_discard_requested", 4)
				_sync._rpc_hand_discard_requested.rpc_id(peer_id, discard_count)
		return
	_play_action_required_if_not_turn_player(player_id)
	_show_hand_discard_selection(player_id, discard_count)


func _show_hand_discard_selection(player_id: int, discard_count: int) -> void:
	_discard_selecting = true
	_discard_player_id = player_id
	_discard_count = discard_count
	_discard_selected_cards.clear()

	# Flip target player's hand face-up so they can see their cards
	var board: Control = player1_board if player_id == 0 else player2_board
	board.set_hand_face_down(false)

	var hand_mgr: CardManager = player1_hand if player_id == 0 else player2_hand
	# Make all cards selectable
	var all_indices: Array[int] = []
	for i in range(hand_mgr.managed_cards.size()):
		all_indices.append(i)
	hand_mgr.enter_selection_mode(all_indices)
	if not hand_mgr.card_selected.is_connected(_on_discard_card_selected):
		hand_mgr.card_selected.connect(_on_discard_card_selected)

	_disable_all_buttons()
	card_select_prompt.text = tr("STR_GB_SELECT_DISCARD_FMT").replace("{N}", str(discard_count))
	action_prompt_panel.visible = true
	btn_confirm.disabled = true


func _on_discard_card_selected(card: Control, _index: int) -> void:
	if not _discard_selecting:
		return

	# Toggle selection: if already selected, deselect; otherwise select
	if card in _discard_selected_cards:
		_discard_selected_cards.erase(card)
		card.modulate = Color.WHITE
	else:
		if _discard_selected_cards.size() < _discard_count:
			_discard_selected_cards.append(card)
			card.modulate = Color(1.0, 0.5, 0.5, 1.0)

	# Update prompt and confirm button
	var remaining: int = _discard_count - _discard_selected_cards.size()
	if remaining > 0:
		card_select_prompt.text = tr("STR_GB_SELECT_MORE_DISCARD_FMT").replace("{N}", str(remaining))
		btn_confirm.disabled = true
	else:
		card_select_prompt.text = tr("STR_GB_PRESS_CONFIRM_DISCARD")
		btn_confirm.text = tr("STR_GB_CONFIRM")
		btn_confirm.disabled = false


func _confirm_hand_discard() -> void:
	var hand_mgr: CardManager = player1_hand if _discard_player_id == 0 else player2_hand

	# Build hand indices from selected cards
	var hand_indices: Array[int] = []
	var player := _get_player_state(_discard_player_id)
	for card in _discard_selected_cards:
		if "card_data" in card:
			var card_id: String = card.card_data.get("id", "")
			for i in range(player.hand.size()):
				if player.hand[i].get("id", "") == card_id and i not in hand_indices:
					hand_indices.append(i)
					break

	# Reset visual state
	for card in _discard_selected_cards:
		card.modulate = Color.WHITE
	_discard_selected_cards.clear()
	_discard_selecting = false

	hand_mgr.exit_selection_mode()
	if hand_mgr.card_selected.is_connected(_on_discard_card_selected):
		hand_mgr.card_selected.disconnect(_on_discard_card_selected)
	action_prompt_panel.visible = false
	btn_confirm.disabled = true

	# Restore hand visibility
	_update_hand_visibility(_get_current_pid())

	if is_multiplayer_game and _discard_player_id != local_player_id:
		return
	if is_multiplayer_game and not NetworkManager.is_host():
		# Client sends choice to host
		var indices_json := JSON.stringify(hand_indices)
		RpcLogger.log_send("hand_discard_resolved", indices_json.length())
		_sync._rpc_hand_discard_resolved.rpc_id(NetworkManager.host_peer_id, indices_json)
	else:
		turn_manager.action_handler.effect_handler.resolve_hand_discard(_discard_player_id, hand_indices)


func _force_cleanup_discard_selection() -> void:
	## Emergency cleanup of discard selection state (e.g. when receiving new action context).
	for card in _discard_selected_cards:
		if is_instance_valid(card):
			card.modulate = Color.WHITE
	_discard_selected_cards.clear()
	_discard_selecting = false
	_discard_player_id = -1
	_discard_count = 0

	for hand_mgr in [player1_hand, player2_hand]:
		hand_mgr.exit_selection_mode()
		if hand_mgr.card_selected.is_connected(_on_discard_card_selected):
			hand_mgr.card_selected.disconnect(_on_discard_card_selected)

	action_prompt_panel.visible = false
	btn_confirm.disabled = true

	_update_hand_visibility(_get_current_pid())


func _on_hand_card_selection_requested(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var indices_json := JSON.stringify(valid_indices)
		_pending_interaction = {"method": "hand_card_selection", "args": [indices_json, prompt, allow_skip]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("hand_card_selection_requested", indices_json.length() + prompt.length() + 1)
				_sync._rpc_hand_card_selection_requested.rpc_id(peer_id, indices_json, prompt, allow_skip)
		return
	_play_action_required_if_not_turn_player(player_id)
	_show_hand_card_selection(player_id, valid_indices, prompt, allow_skip)


func _show_hand_card_selection(player_id: int, valid_indices: Array[int], prompt: String, allow_skip: bool) -> void:
	_hand_card_selecting = true
	_hand_card_player_id = player_id
	_hand_card_allow_skip = allow_skip

	# Flip target player's hand face-up so they can see their cards
	var board: Control = player1_board if player_id == 0 else player2_board
	board.set_hand_face_down(false)

	# Translate player.hand indices to visual managed_cards indices
	var visual_indices := _hand_indices_to_visual(valid_indices, board, player_id)

	var hand_mgr: CardManager = player1_hand if player_id == 0 else player2_hand
	hand_mgr.enter_selection_mode(visual_indices)
	if not hand_mgr.card_selected.is_connected(_on_hand_card_clicked):
		hand_mgr.card_selected.connect(_on_hand_card_clicked)

	_disable_all_buttons()
	card_select_prompt.text = _resolve_translated_text(prompt)
	action_prompt_panel.visible = true

	if allow_skip:
		btn_confirm.text = tr("STR_GB_SKIP")
		btn_confirm.disabled = false
	else:
		btn_confirm.disabled = true


func _on_hand_card_clicked(card: Control, _index: int) -> void:
	if not _hand_card_selecting:
		return

	# Single-select: find the hand index and resolve immediately
	var hand_mgr: CardManager = player1_hand if _hand_card_player_id == 0 else player2_hand
	var player := _get_player_state(_hand_card_player_id)
	var hand_index: int = -1
	if "card_data" in card:
		var card_id: String = card.card_data.get("id", "")
		for i in range(player.hand.size()):
			if player.hand[i].get("id", "") == card_id:
				hand_index = i
				break

	_cleanup_hand_card_selection(hand_mgr)

	if is_multiplayer_game and _hand_card_player_id != local_player_id:
		return
	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("hand_card_selection_resolved", 4)
		_sync._rpc_hand_card_selection_resolved.rpc_id(NetworkManager.host_peer_id, hand_index)
	else:
		turn_manager.action_handler.effect_handler.resolve_hand_card_selection(hand_index)


func _skip_hand_card_selection() -> void:
	var hand_mgr: CardManager = player1_hand if _hand_card_player_id == 0 else player2_hand
	_cleanup_hand_card_selection(hand_mgr)

	if is_multiplayer_game and _hand_card_player_id != local_player_id:
		return
	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("hand_card_selection_resolved", 4)
		_sync._rpc_hand_card_selection_resolved.rpc_id(NetworkManager.host_peer_id, -1)
	else:
		turn_manager.action_handler.effect_handler.resolve_hand_card_selection(-1)


func _cleanup_hand_card_selection(hand_mgr: CardManager) -> void:
	_hand_card_selecting = false
	hand_mgr.exit_selection_mode()
	if hand_mgr.card_selected.is_connected(_on_hand_card_clicked):
		hand_mgr.card_selected.disconnect(_on_hand_card_clicked)
	action_prompt_panel.visible = false
	btn_confirm.text = tr("STR_GB_CONFIRM")
	btn_confirm.disabled = true
	_update_hand_visibility(_get_current_pid())


func _on_zone_target_requested(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var zones_json := JSON.stringify(valid_zones)
		_pending_interaction = {"method": "zone_target", "args": [target_player_id, zones_json, prompt, allow_skip]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("zone_target_requested", 4 + zones_json.length() + prompt.length() + 1)
				_sync._rpc_zone_target_requested.rpc_id(peer_id, target_player_id, zones_json, prompt, allow_skip)
		return
	_show_zone_target_selection(player_id, target_player_id, valid_zones, prompt, allow_skip)


func _show_zone_target_selection(player_id: int, target_player_id: int, valid_zones: Array[int], prompt: String, allow_skip: bool = false) -> void:
	_zone_target_selecting = true
	_zone_target_player_id = player_id
	_zone_target_board_pid = target_player_id
	_zone_target_valid_zones = valid_zones
	_zone_target_allow_skip = allow_skip

	_disable_all_buttons()
	card_select_prompt.text = _resolve_translated_text(prompt)
	action_prompt_panel.visible = true

	if allow_skip:
		btn_confirm.text = tr("STR_GB_SKIP")
		btn_confirm.disabled = false
	else:
		btn_confirm.disabled = true

	# Highlight valid zones on the target player's board
	var board: Control = player1_board if target_player_id == 0 else player2_board
	board.highlight_valid_zones(valid_zones)
	for i in range(board.zone_slots.size()):
		var slot: Slot = board.zone_slots[i]
		if slot and i in valid_zones:
			slot.in_selection_mode = true
			if not slot.slot_clicked.is_connected(_on_zone_target_slot_clicked):
				slot.slot_clicked.connect(_on_zone_target_slot_clicked)


func _on_zone_target_slot_clicked(zone_num: int, _pid: int) -> void:
	if not _zone_target_selecting:
		return
	var zone_idx: int = zone_num - 1
	if zone_idx not in _zone_target_valid_zones:
		return
	_finish_zone_target(zone_idx)


func _skip_zone_target() -> void:
	_finish_zone_target(-1)


func _finish_zone_target(zone_idx: int) -> void:
	# Clean up UI
	var board: Control = player1_board if _zone_target_board_pid == 0 else player2_board
	board.clear_highlights()
	for i in range(board.zone_slots.size()):
		var slot: Slot = board.zone_slots[i]
		if slot:
			slot.in_selection_mode = false
			if slot.slot_clicked.is_connected(_on_zone_target_slot_clicked):
				slot.slot_clicked.disconnect(_on_zone_target_slot_clicked)

	_zone_target_selecting = false
	_zone_target_allow_skip = false
	action_prompt_panel.visible = false
	btn_confirm.disabled = true

	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("zone_target_resolved", 4)
		_sync._rpc_zone_target_resolved.rpc_id(NetworkManager.host_peer_id, zone_idx)
	else:
		turn_manager.action_handler.effect_handler.resolve_zone_target(zone_idx)


func _on_strategy_target_requested(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var indices_json := JSON.stringify(valid_indices)
		_pending_interaction = {"method": "strategy_target", "args": [target_player_id, indices_json, prompt]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("strategy_target_requested", 4 + indices_json.length() + prompt.length())
				_sync._rpc_strategy_target_requested.rpc_id(peer_id, target_player_id, indices_json, prompt)
		return
	_show_strategy_target_selection(player_id, target_player_id, valid_indices, prompt)


func _show_strategy_target_selection(player_id: int, target_player_id: int, valid_indices: Array[int], prompt: String) -> void:
	_strategy_target_selecting = true
	_strategy_target_player_id = player_id
	_strategy_target_board_pid = target_player_id
	_strategy_target_valid_indices = valid_indices

	_disable_all_buttons()
	card_select_prompt.text = _resolve_translated_text(prompt)
	action_prompt_panel.visible = true

	# Highlight valid strategy slots on the target player's board
	var board: Control = player1_board if target_player_id == 0 else player2_board
	for i in range(board.strategy_slots.size()):
		var slot: Slot = board.strategy_slots[i]
		if slot and i in valid_indices:
			slot.set_highlighted(true)
			slot.in_selection_mode = true
			if not slot.slot_clicked.is_connected(_on_strategy_target_slot_clicked):
				slot.slot_clicked.connect(_on_strategy_target_slot_clicked.bind(i))


func _on_strategy_target_slot_clicked(_zone_num: int, _pid: int, strategy_idx: int) -> void:
	if not _strategy_target_selecting:
		return
	if strategy_idx not in _strategy_target_valid_indices:
		return
	_finish_strategy_target(strategy_idx)


func _finish_strategy_target(strategy_idx: int) -> void:
	# Clean up UI
	var board: Control = player1_board if _strategy_target_board_pid == 0 else player2_board
	for i in range(board.strategy_slots.size()):
		var slot: Slot = board.strategy_slots[i]
		if slot:
			slot.set_highlighted(false)
			slot.in_selection_mode = false
			if slot.slot_clicked.is_connected(_on_strategy_target_slot_clicked):
				slot.slot_clicked.disconnect(_on_strategy_target_slot_clicked)

	_strategy_target_selecting = false
	action_prompt_panel.visible = false
	btn_confirm.disabled = true

	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("strategy_target_resolved", 4)
		_sync._rpc_strategy_target_resolved.rpc_id(NetworkManager.host_peer_id, strategy_idx)
	else:
		turn_manager.action_handler.effect_handler.resolve_strategy_target(strategy_idx)


func _on_choice_requested(player_id: int, options: Array[String], prompt: String) -> void:
	if is_bot_game and player_id == bot_player.bot_player_id:
		return
	# Card art behind each option (parallel to options; "" = text-only).
	var card_ids: Array[String] = []
	if turn_manager:
		card_ids = turn_manager.action_handler.effect_handler.choice_card_ids
	if is_multiplayer_game and player_id != local_player_id:
		_flush_broadcast()
		var options_json := JSON.stringify(options)
		var card_ids_json := JSON.stringify(card_ids)
		_pending_interaction = {"method": "choice", "args": [options_json, prompt, card_ids_json]}
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				RpcLogger.log_send("choice_requested", options_json.length() + prompt.length())
				_sync._rpc_choice_requested.rpc_id(peer_id, options_json, prompt, card_ids_json)
		return
	_show_choice_selection(player_id, options, prompt, card_ids)


func _show_choice_selection(player_id: int, options: Array[String], prompt: String, card_ids: Array[String] = []) -> void:
	_choice_selecting = true
	_choice_player_id = player_id

	_disable_all_buttons()
	# Hide the normal action button rows so only choice buttons show
	_set_action_buttons_visible(false)
	card_select_prompt.text = _resolve_translated_text(prompt)
	action_prompt_panel.visible = true

	# Choice buttons live in their own OPAQUE panel so they never visually
	# bleed into the turn tracker behind them, anchored above the hand
	# toggle/sort buttons so they never cover those either. The button list
	# scrolls when there are more options than fit.
	_choice_panel = PanelContainer.new()
	_choice_panel.name = "ChoicePanel"
	# Transparent background — the player can see the board behind the
	# action buttons; only the buttons themselves are visible.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	_choice_panel.add_theme_stylebox_override("panel", panel_style)
	_choice_panel.z_index = 56

	# Bottom edge: clear the mobile bottom bar AND always sit above the hand
	# toggle/sort button stack (both layouts position that stack differently).
	var viewport_h: float = _board.get_viewport_rect().size.y
	var bottom_y: float = viewport_h - (130.0 if _is_mobile_layout else 12.0)
	var hand_stack: Control = _board.get_node_or_null("HandButtonStack")
	if hand_stack and hand_stack.visible:
		bottom_y = minf(bottom_y, hand_stack.get_global_rect().position.y - 8.0)
	# Explicitly position the rect with its BOTTOM edge at bottom_y — do not
	# rely on grow directions (a min-size overflow expands DOWNWARD from the
	# anchor point, which is how the panel ended up over/below the screen).
	var panel_width := 372.0 # 360 scroll + 12 stylebox margins
	var panel_margins := 12.0
	var per_btn: float = 64.0
	var max_height: float = bottom_y - 56.0 # keep the prompt text visible above
	var est_height: float = minf(options.size() * per_btn + 12.0, max_height)
	_choice_panel.anchor_left = 1.0
	_choice_panel.anchor_right = 1.0
	_choice_panel.anchor_top = 0.0
	_choice_panel.anchor_bottom = 0.0
	_choice_panel.offset_left = -6.0 - panel_width
	_choice_panel.offset_right = -6.0
	_choice_panel.offset_top = bottom_y - (est_height + panel_margins)
	_choice_panel.offset_bottom = bottom_y

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(360.0, est_height)
	_choice_panel.add_child(scroll)
	# After the first layout pass, shrink-wrap to the buttons' real (wrapped)
	# height — no gap under the last button — and re-pin the bottom edge.
	_fit_choice_panel.call_deferred(scroll, bottom_y, max_height)

	_choice_container = VBoxContainer.new()
	_choice_container.name = "ChoiceContainer"
	_choice_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_container.add_theme_constant_override("separation", 4)
	scroll.add_child(_choice_container)
	add_child(_choice_panel)

	for i in range(options.size()):
		var btn := Button.new()
		btn.text = _resolve_translated_text(options[i])
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size.x = 340
		btn.custom_minimum_size.y = 60 if _is_mobile_layout else 0
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _is_mobile_layout:
			btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		# Card art thumb (deck-list-style top crop; strategy = upright center
		# square) so the player can see WHICH card each ability belongs to.
		if i < card_ids.size() and not card_ids[i].is_empty():
			var thumb := OverlayGridUtil.get_choice_thumb(card_ids[i])
			if thumb:
				btn.icon = thumb
				btn.expand_icon = true
				btn.add_theme_constant_override("icon_max_width", 48)
				btn.custom_minimum_size.y = maxf(btn.custom_minimum_size.y, 56.0)
		btn.pressed.connect(_on_choice_button_pressed.bind(i))
		_choice_container.add_child(btn)
		_choice_buttons.append(btn)


## Deferred: match the scroll viewport to the laid-out button column so the
## panel hugs its content (capped at max_height — beyond that it scrolls),
## keeping the BOTTOM edge pinned at bottom_y so the panel grows upward.
func _fit_choice_panel(scroll: ScrollContainer, bottom_y: float, max_height: float) -> void:
	if not is_instance_valid(scroll) or _choice_container == null or not is_instance_valid(_choice_container):
		return
	if _choice_panel == null or not is_instance_valid(_choice_panel):
		return
	var content_h: float = minf(_choice_container.size.y + 2.0, max_height)
	scroll.custom_minimum_size.y = content_h
	_choice_panel.offset_top = bottom_y - (content_h + 12.0)
	_choice_panel.offset_bottom = bottom_y


func _on_choice_button_pressed(index: int) -> void:
	if not _choice_selecting:
		return
	_cleanup_choice_selection()

	if is_multiplayer_game and not NetworkManager.is_host():
		RpcLogger.log_send("choice_resolved", 4)
		_sync._rpc_choice_resolved.rpc_id(NetworkManager.host_peer_id, index)
	else:
		turn_manager.action_handler.effect_handler.resolve_choice(index)


func _cleanup_choice_selection() -> void:
	_choice_selecting = false
	_choice_buttons.clear()
	if _choice_panel:
		# Reparent-free immediately so a subsequent choice_requested in the
		# same frame gets a clean state.
		remove_child(_choice_panel)
		_choice_panel.queue_free()
		_choice_panel = null
		_choice_container = null
	elif _choice_container:
		_choice_container.queue_free()
		_choice_container = null
	action_prompt_panel.visible = false
	# Restore normal action button rows
	_set_action_buttons_visible(true)
