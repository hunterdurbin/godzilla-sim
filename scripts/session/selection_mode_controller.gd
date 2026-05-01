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
##   - Hand sorting / visual-index translation (assumes hand index ==
##     visual index).
##   - Multi-card selection (used by hand-discard prompts — those go
##     through EffectUIRouter).
##   - Snap-preview animation while dragging (designer can layer on).

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

# Confirm-pass state: settings-gated dialog before submitting PASS
var _confirming_pass: bool = false

# Generic-confirmation state: when GameBoardBase delegates an
# auto-confirm prompt to us, we show it via the action panel and
# fire this callback on Confirm.
var _confirmation_callback: Callable = Callable()

# Drag-to-zone state (parallel input path to clicks)
var _drag_card: Control = null
var _drag_player_board: Node = null
var _drag_action: int = CardEnums.ActionType.PASS
var _drag_valid_zones: Array[int] = []
var _drag_can_rage: bool = false
var _drag_can_invade: bool = false


func _init(session: GameSession, action_panel: Control, board_root: Node) -> void:
	_session = session
	_action_panel = action_panel
	_board_root = board_root


## Connect signals. Call after the session is started.
func bind() -> void:
	if _action_panel:
		_action_panel.action_pressed.connect(_on_action_pressed)
		_action_panel.cancel_pressed.connect(_on_cancel_pressed)
		_action_panel.confirm_pressed.connect(_on_confirm_pressed)
	if _session and _session.turn_manager:
		_session.turn_manager.awaiting_player_action.connect(_on_awaiting_action)
		_session.turn_manager.phase_ended.connect(_on_phase_ended)
	_collect_player_boards(_board_root)
	# Connect drag signals on each player board's hand_manager (if present).
	for pb in _player_boards:
		if pb.hand_manager:
			if not pb.hand_manager.hand_card_drag_started.is_connected(_on_hand_drag_started):
				pb.hand_manager.hand_card_drag_started.connect(_on_hand_drag_started.bind(pb))
			if not pb.hand_manager.hand_card_drag_ended.is_connected(_on_hand_drag_ended):
				pb.hand_manager.hand_card_drag_ended.connect(_on_hand_drag_ended.bind(pb))


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
		# Settings-gated pass confirmation. If the per-player setting is on,
		# show a "End your turn?" prompt instead of submitting immediately.
		var pid: int = _session.current_player_id()
		if _confirm_pass_for(pid):
			_enter_pass_confirmation()
			return
		_clear_selection()
		_session.submit_action(CardEnums.ActionType.PASS, {})
		return

	# Card-action: query rules for the playable hand indices
	var playable: Array[int] = _query_playable(action)
	if playable.is_empty():
		return

	_pending_action = action
	_enter_card_selection(playable)


## Returns true if the per-player "confirm before passing the main phase"
## setting is on for this player_id. Falls back to the global GameSettings
## value if no per-player override exists.
func _confirm_pass_for(_pid: int) -> bool:
	# GameSettings is the source of truth; per-player overrides live on
	# game_board.gd today and aren't migrated yet — designers who want
	# per-player toggles can pass them via a callable later.
	return GameSettings.get("confirm_main_phase_pass") if "confirm_main_phase_pass" in GameSettings else false


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
	if _confirming_pass:
		_cancel_pass_confirmation()
		return
	if _confirmation_callback.is_valid():
		# Cancel = decline the auto-confirm prompt. There's no public
		# API for "I declined" today, so we just close the prompt.
		_confirmation_callback = Callable()
		if _action_panel:
			_action_panel.hide_prompt()
		_refresh_buttons()
		return
	if _waiting_for_card_select or _waiting_for_zone_select:
		_clear_selection()
		_refresh_buttons()


func _on_confirm_pressed() -> void:
	if _confirming_pass:
		_confirming_pass = false
		_action_panel.hide_prompt()
		_clear_selection()
		_session.submit_action(CardEnums.ActionType.PASS, {})
		return
	if _confirmation_callback.is_valid():
		var cb := _confirmation_callback
		_confirmation_callback = Callable()
		if _action_panel:
			_action_panel.hide_prompt()
		_refresh_buttons()
		cb.call()


## Show a Confirm/Cancel prompt to the local player. Used by
## GameBoardBase to surface TurnManager.confirmation_requested events
## when the corresponding GameSettings auto-flag is off. On Confirm,
## `on_confirm` fires; on Cancel, the prompt closes silently.
func prompt_confirmation(prompt: String, on_confirm: Callable) -> void:
	if _action_panel == null:
		# No panel — auto-confirm to keep the engine moving.
		on_confirm.call()
		return
	_confirmation_callback = on_confirm
	_action_panel.show_prompt(prompt, true)


# --- Pass confirmation ---

func _enter_pass_confirmation() -> void:
	_confirming_pass = true
	if _action_panel:
		_action_panel.show_prompt(TranslationServer.translate("STR_GB_END_MAIN_QUESTION"), true)


func _cancel_pass_confirmation() -> void:
	_confirming_pass = false
	if _action_panel:
		_action_panel.hide_prompt()
	_refresh_buttons()


# --- Drag-to-zone (parallel input path) ---

func _on_hand_drag_started(card: Control, player_board: Node) -> void:
	if _waiting_for_card_select or _waiting_for_zone_select or _confirming_pass:
		return
	if not _session or not _session.is_running():
		return
	if NetworkManager.is_multiplayer() and not NetworkManager.is_local_player_turn(_session.current_player_id()):
		return
	# Drag must come from the active player's hand
	if player_board != _get_active_player_board():
		return
	if not "card_data" in card or card.card_data.is_empty():
		return

	_drag_card = card
	_drag_player_board = player_board
	_drag_action = CardEnums.ActionType.PASS
	_drag_valid_zones = []
	_drag_can_rage = false
	_drag_can_invade = false

	var card_data: Dictionary = card.card_data
	var card_id: String = card_data.get("id", "")
	var hand_idx: int = _find_hand_index_by_id(card_id)
	if hand_idx < 0:
		return

	var player := _session.game_state.get_current_player()
	var opponent := _session.game_state.get_opponent_of_current()
	var rules := _session.rules_engine
	var card_type = card_data.get("card_type", -1)

	match card_type:
		CardEnums.CardType.BATTLE:
			if hand_idx in rules.get_playable_battle_cards(player, opponent):
				_drag_valid_zones = rules.get_valid_zones_for_card(card_data, player, opponent)
				_drag_action = CardEnums.ActionType.PLAY_BATTLE
		CardEnums.CardType.MONSTER:
			if hand_idx in rules.get_playable_monsters(player):
				var mz: int = player.monster_zone - 1
				if mz >= 0 and mz < 8:
					_drag_valid_zones = [mz]
					_drag_action = CardEnums.ActionType.PLAY_MONSTER
			if hand_idx in rules.get_monster_cards_for_rage(player):
				_drag_can_rage = true
		CardEnums.CardType.STRATEGY:
			if hand_idx in rules.get_playable_strategy_cards(player):
				_drag_action = CardEnums.ActionType.PLAY_STRATEGY

	# Any card with invasion_icon > 0 can be discarded for invasion
	if card_data.get("invasion_icon", 0) > 0:
		if hand_idx in rules.get_discardable_cards_for_invade(player, opponent):
			_drag_can_invade = true

	# Highlight valid drop targets
	if not _drag_valid_zones.is_empty() and player_board.has_method("highlight_valid_zones"):
		player_board.highlight_valid_zones(_drag_valid_zones)
	if _drag_action == CardEnums.ActionType.PLAY_STRATEGY and player_board.has_method("highlight_strategy_zones"):
		player_board.highlight_strategy_zones()
	if _drag_can_rage and player_board.has_method("highlight_rage_zone"):
		player_board.highlight_rage_zone(true)
	if _drag_can_invade and player_board.has_method("highlight_discard_zone"):
		player_board.highlight_discard_zone(true)


func _on_hand_drag_ended(card: Control, player_board: Node) -> void:
	if player_board.has_method("clear_highlights"):
		player_board.clear_highlights()

	# If drag never registered as a valid action, just clean up
	var has_target: bool = (
		not _drag_valid_zones.is_empty()
		or _drag_action == CardEnums.ActionType.PLAY_STRATEGY
		or _drag_can_rage
		or _drag_can_invade
	)
	if _drag_card != card or not has_target:
		_reset_drag_state()
		return

	# Detect the dropped target by mouse position
	var mouse_pos: Vector2 = player_board.get_global_mouse_position()
	var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
	var hand_idx: int = _find_hand_index_by_id(card_id)
	if hand_idx < 0:
		_reset_drag_state()
		return

	# Rage zone drop (monster card → rage)
	if _drag_can_rage and "rage_display" in player_board and player_board.rage_display:
		var rect := Rect2(player_board.rage_display.global_position, player_board.rage_display.size)
		if rect.has_point(mouse_pos):
			player_board.hand_manager.drop_handled = true
			_reset_drag_state()
			_session.submit_action(CardEnums.ActionType.GAIN_RAGE, {"hand_index": hand_idx})
			return

	# Discard zone drop (any invasion-icon card → invade)
	if _drag_can_invade and "discard_display" in player_board and player_board.discard_display:
		var rect := Rect2(player_board.discard_display.global_position, player_board.discard_display.size)
		if rect.has_point(mouse_pos):
			player_board.hand_manager.drop_handled = true
			_reset_drag_state()
			_session.submit_action(CardEnums.ActionType.INVADE, {"hand_index": hand_idx})
			return

	# Strategy slot drop (strategy cards → strategy zone, no zone_index)
	if _drag_action == CardEnums.ActionType.PLAY_STRATEGY:
		for slot in player_board.strategy_slots:
			if slot and not slot.has_card():
				var rect := Rect2(slot.global_position, slot.size)
				if rect.has_point(mouse_pos):
					player_board.hand_manager.drop_handled = true
					_reset_drag_state()
					_session.submit_action(CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": hand_idx})
					return

	# Battle / monster zone drop
	for i in _drag_valid_zones:
		var slot = player_board.zone_slots[i]
		var rect := Rect2(slot.global_position, slot.size)
		if rect.has_point(mouse_pos):
			player_board.hand_manager.drop_handled = true
			card.is_locked_in_zone = true
			var params := {"hand_index": hand_idx}
			if _drag_action != CardEnums.ActionType.PLAY_MONSTER:
				params["zone_index"] = i
			var action := _drag_action
			_reset_drag_state()
			_session.submit_action(action, params)
			return

	_reset_drag_state()


func _reset_drag_state() -> void:
	_drag_card = null
	_drag_player_board = null
	_drag_action = CardEnums.ActionType.PASS
	_drag_valid_zones.clear()
	_drag_can_rage = false
	_drag_can_invade = false


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
