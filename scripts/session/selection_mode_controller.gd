class_name SelectionModeController
extends RefCounted

## Drives the click-based action-button → hand-card → zone selection
## flow that game_board.gd inlines today. Lives as a controller class
## (no scene), constructed by GameBoardBase when an ActionPanel is
## present in the tree.
##
## What it owns:
##   - Listens to ActionPanel.action_pressed / cancel_pressed.
##   - On action press: validates turn ownership + rules, enters card
##     selection mode on the active player's hand_manager.
##   - On card select: either submits directly (PLAY_STRATEGY,
##     GAIN_RAGE, PLAY_MONSTER, INVADE) or enters zone selection
##     (PLAY_BATTLE).
##   - On zone select: submits the action with the chosen indices.
##   - On phase or awaiting-action signals: enables/disables the
##     correct subset of action buttons based on the rules engine.
##
## Out of scope (designer extends if needed):
##   - Drag-to-zone (game_board's parallel input path).
##   - Hand sorting / visual-index translation (assumes hand index ==
##     visual index).
##   - Multi-card selection (used by hand-discard prompts — those go
##     through EffectUIRouter).
##   - Auto-confirm / pass-confirmation dialogs (settings-gated UX).

const _CARD_ACTIONS: Array[int] = [
	CardEnums.ActionType.PLAY_BATTLE,
	CardEnums.ActionType.PLAY_STRATEGY,
	CardEnums.ActionType.GAIN_RAGE,
	CardEnums.ActionType.PLAY_MONSTER,
	CardEnums.ActionType.INVADE,
]

var _session: GameSession
var _action_panel: Control
var _board_root: Node
var _player_boards: Array = []

var _pending_action: int = CardEnums.ActionType.PASS
var _selected_card_data: Dictionary = {}
var _waiting_for_card_select: bool = false
var _waiting_for_zone_select: bool = false
var _zone_select_valid: Array[int] = []
var _selection_hand_manager: Node = null
var _selection_player_board: Node = null
var _connected_zone_slots: Array = []


func _init(session: GameSession, action_panel: Control, board_root: Node) -> void:
	_session = session
	_action_panel = action_panel
	_board_root = board_root


## Connect signals. Call after the session is started.
func bind() -> void:
	if _action_panel:
		_action_panel.action_pressed.connect(_on_action_pressed)
		_action_panel.cancel_pressed.connect(_on_cancel_pressed)
	if _session and _session.turn_manager:
		_session.turn_manager.awaiting_player_action.connect(_on_awaiting_action)
		_session.turn_manager.phase_ended.connect(_on_phase_ended)
	_collect_player_boards(_board_root)


# --- Discovery ---

func _collect_player_boards(node: Node) -> void:
	for child in node.get_children():
		# PlayerBoard is class_name'd; check via script
		if child.get_script() and str(child.get_script().get_global_name()) == "PlayerBoard":
			_player_boards.append(child)
		else:
			_collect_player_boards(child)


func _get_active_player_board() -> Node:
	if not _session or not _session.is_running():
		return null
	var pid: int = _session.current_player_id()
	for pb in _player_boards:
		if pb.player_id == pid:
			return pb
	return null


# --- Action handlers ---

func _on_action_pressed(action: int) -> void:
	if not _session or not _session.is_running():
		return
	# Turn-ownership: in multiplayer the local player must own the turn
	# before they can submit any action. In solo, always allow.
	if NetworkManager.is_multiplayer():
		var current_pid: int = _session.current_player_id()
		if not NetworkManager.is_local_player_turn(current_pid):
			return

	if action == CardEnums.ActionType.PASS:
		_clear_selection()
		_session.submit_action(CardEnums.ActionType.PASS, {})
		return

	# Card-action: query rules for the playable hand indices
	var playable: Array[int] = _query_playable(action)
	if playable.is_empty():
		return

	_pending_action = action
	_enter_card_selection(playable)


func _query_playable(action: int) -> Array[int]:
	if _session == null or not _session.is_running():
		return []
	var state := _session.game_state
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()
	var rules := _session.rules_engine
	match action:
		CardEnums.ActionType.PLAY_BATTLE:
			return rules.get_playable_battle_cards(player, opponent)
		CardEnums.ActionType.PLAY_STRATEGY:
			return rules.get_playable_strategy_cards(player)
		CardEnums.ActionType.GAIN_RAGE:
			return rules.get_monster_cards_for_rage(player)
		CardEnums.ActionType.PLAY_MONSTER:
			return rules.get_playable_monsters(player)
		CardEnums.ActionType.INVADE:
			return rules.get_discardable_cards_for_invade(player, opponent)
	return []


func _on_cancel_pressed() -> void:
	if _waiting_for_card_select or _waiting_for_zone_select:
		_clear_selection()
		_refresh_buttons()


# --- Card selection ---

func _enter_card_selection(valid_indices: Array[int]) -> void:
	_waiting_for_card_select = true
	_action_panel.show_prompt(_prompt_for_action(_pending_action))
	var board := _get_active_player_board()
	if board == null or board.hand_manager == null:
		_clear_selection()
		return
	_selection_player_board = board
	_selection_hand_manager = board.hand_manager
	board.hand_manager.enter_selection_mode(valid_indices)
	if not board.hand_manager.card_selected.is_connected(_on_hand_card_selected):
		board.hand_manager.card_selected.connect(_on_hand_card_selected)


func _prompt_for_action(action: int) -> String:
	match action:
		CardEnums.ActionType.PLAY_BATTLE: return "Select a BATTLE card to play:"
		CardEnums.ActionType.PLAY_STRATEGY: return "Select a STRATEGY card:"
		CardEnums.ActionType.GAIN_RAGE: return "Select a card to discard for Rage:"
		CardEnums.ActionType.PLAY_MONSTER: return "Select a MONSTER card to play:"
		CardEnums.ActionType.INVADE: return "Select a card to discard for Invasion:"
	return ""


func _on_hand_card_selected(card: Control, _visual_index: int) -> void:
	if not _waiting_for_card_select:
		return
	_selected_card_data = card.card_data if "card_data" in card else {}
	var card_id: String = _selected_card_data.get("id", "")
	if card_id.is_empty():
		return
	# PLAY_BATTLE goes to zone selection; the rest submit immediately.
	if _pending_action == CardEnums.ActionType.PLAY_BATTLE:
		_enter_zone_selection()
		return
	var hand_idx := _find_hand_index_by_id(card_id)
	_clear_selection()
	if hand_idx >= 0:
		_session.submit_action(_pending_action, {"hand_index": hand_idx})


func _find_hand_index_by_id(card_id: String) -> int:
	if not _session or not _session.is_running():
		return -1
	var player := _session.game_state.get_current_player()
	for i in range(player.hand.size()):
		if player.hand[i].get("id", "") == card_id:
			return i
	return -1


# --- Zone selection (PLAY_BATTLE only) ---

func _enter_zone_selection() -> void:
	_waiting_for_card_select = false
	_waiting_for_zone_select = true
	_action_panel.show_prompt("Select a zone:")
	var board := _selection_player_board
	if board == null:
		_clear_selection()
		return

	var rules := _session.rules_engine
	var state := _session.game_state
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()
	var valid_zones: Array[int] = rules.get_valid_zones_for_card(_selected_card_data, player, opponent)
	_zone_select_valid = valid_zones

	if board.hand_manager:
		board.hand_manager.exit_selection_mode()
	if board.has_method("highlight_valid_zones"):
		board.highlight_valid_zones(valid_zones)
	for i in range(board.zone_slots.size()):
		var slot = board.zone_slots[i]
		if i in valid_zones:
			slot.in_selection_mode = true
			slot.accept_cards = true
			var cb := _on_zone_slot_clicked.bind(i)
			if not slot.slot_clicked.is_connected(cb):
				slot.slot_clicked.connect(cb)
				_connected_zone_slots.append([slot, cb])


func _on_zone_slot_clicked(_zone_number: int, _player_id: int, zone_index: int) -> void:
	if not _waiting_for_zone_select:
		return
	if zone_index not in _zone_select_valid:
		return
	var hand_idx := _find_hand_index_by_id(_selected_card_data.get("id", ""))
	_clear_selection()
	if hand_idx >= 0:
		_session.submit_action(CardEnums.ActionType.PLAY_BATTLE, {
			"hand_index": hand_idx,
			"zone_index": zone_index,
		})


# --- Cleanup ---

func _clear_selection() -> void:
	_waiting_for_card_select = false
	_waiting_for_zone_select = false
	_pending_action = CardEnums.ActionType.PASS
	_selected_card_data = {}
	_zone_select_valid.clear()
	if _selection_hand_manager:
		_selection_hand_manager.exit_selection_mode()
		if _selection_hand_manager.card_selected.is_connected(_on_hand_card_selected):
			_selection_hand_manager.card_selected.disconnect(_on_hand_card_selected)
		_selection_hand_manager = null
	if _selection_player_board and _selection_player_board.has_method("highlight_valid_zones"):
		_selection_player_board.highlight_valid_zones([])
	for entry in _connected_zone_slots:
		var slot = entry[0]
		var cb: Callable = entry[1]
		if slot and slot.slot_clicked.is_connected(cb):
			slot.slot_clicked.disconnect(cb)
		if slot:
			slot.in_selection_mode = false
	_connected_zone_slots.clear()
	_selection_player_board = null
	if _action_panel:
		_action_panel.hide_prompt()


# --- Button-state refresh ---

func _on_awaiting_action(valid_actions: Array) -> void:
	if _waiting_for_card_select or _waiting_for_zone_select:
		return  # Don't disturb in-flight selection
	_refresh_buttons_with(valid_actions)


func _on_phase_ended(_phase) -> void:
	_clear_selection()


func _refresh_buttons() -> void:
	if not _session or not _session.is_running():
		return
	var valid_actions := _session.rules_engine.get_valid_actions(_session.game_state)
	_refresh_buttons_with(valid_actions)


func _refresh_buttons_with(valid_actions: Array) -> void:
	if _action_panel == null:
		return
	# Enable a button only if it's local player's turn AND the action is in
	# the rules-engine's valid set.
	var local_turn: bool = true
	if NetworkManager.is_multiplayer():
		local_turn = NetworkManager.is_local_player_turn(_session.current_player_id())
	for action in [
		CardEnums.ActionType.PLAY_BATTLE,
		CardEnums.ActionType.PLAY_STRATEGY,
		CardEnums.ActionType.GAIN_RAGE,
		CardEnums.ActionType.PLAY_MONSTER,
		CardEnums.ActionType.INVADE,
		CardEnums.ActionType.PASS,
	]:
		_action_panel.set_button_enabled(action, local_turn and action in valid_actions)
