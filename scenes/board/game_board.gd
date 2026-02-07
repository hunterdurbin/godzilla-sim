extends Control

## Main game controller. Orchestrates the UI, TurnManager, and both PlayerBoards.
## In multiplayer, the host runs TurnManager and broadcasts state to the client.
## The client receives state via RPC and sends actions back to the host.

var turn_manager: TurnManager  # Only exists on host/solo
var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")

# Multiplayer state
var is_multiplayer_game: bool = false
var local_player_id: int = 0  # 0 for host/solo, 1 for client

# Client-side state (populated from host RPCs)
var _client_players: Array[PlayerState] = []
var _client_current_player_id: int = 0
var _client_playable: Dictionary = {}  # Playable card/zone indices from host

# UI references
@onready var player1_board: Control = $VBoxContainer/Player1Board
@onready var player2_board: Control = $VBoxContainer/Player2Board
@onready var action_panel: Control = $VBoxContainer/BottomHUD/ActionPanel
@onready var phase_label: Label = $VBoxContainer/TopHUD/PhaseLabel
@onready var turn_label: Label = $VBoxContainer/TopHUD/TurnLabel
@onready var log_output: RichTextLabel = $VBoxContainer/BottomHUD/LogPanel/LogOutput
@onready var end_game_panel: Control = $EndGamePanel
@onready var card_select_prompt: Label = $VBoxContainer/TopHUD/CardSelectPromptTop

# Hand references
@onready var player1_hand: Node2D = $Player1Hand
@onready var player2_hand: Node2D = $Player2Hand
@onready var player1_hand_space: Control = $VBoxContainer/Player1HandSpace
@onready var player2_hand_space: Control = $VBoxContainer/Player2HandSpace

# Action buttons
@onready var btn_play_battle: Button = $VBoxContainer/BottomHUD/ActionPanel/Row1/PlayBattle
@onready var btn_play_strategy: Button = $VBoxContainer/BottomHUD/ActionPanel/Row1/PlayStrategy
@onready var btn_gain_rage: Button = $VBoxContainer/BottomHUD/ActionPanel/Row1/GainRage
@onready var btn_play_monster: Button = $VBoxContainer/BottomHUD/ActionPanel/Row2/PlayMonster
@onready var btn_invade: Button = $VBoxContainer/BottomHUD/ActionPanel/Row2/Invade
@onready var btn_pass: Button = $VBoxContainer/BottomHUD/ActionPanel/Row2/Pass

# Deck search UI references
@onready var deck_search_overlay: Control = $DeckSearchOverlay
@onready var deck_search_prompt: Label = $DeckSearchOverlay/DeckSearchPanel/VBox/PromptLabel
@onready var deck_search_grid: GridContainer = $DeckSearchOverlay/DeckSearchPanel/VBox/ScrollContainer/CardGrid
@onready var deck_search_skip: Button = $DeckSearchOverlay/DeckSearchPanel/VBox/SkipButton

# State tracking
var pending_action: CardEnums.ActionType = CardEnums.ActionType.PASS
var waiting_for_card_select: bool = false
var waiting_for_zone_select: bool = false
var selected_card_id: String = ""

# Drag-to-zone state
var _drag_card: Control = null
var _drag_valid_zones: Array[int] = []
var _drag_action: CardEnums.ActionType = CardEnums.ActionType.PASS


func _ready() -> void:
	is_multiplayer_game = NetworkManager.is_multiplayer()
	local_player_id = NetworkManager.get_local_player_id() if is_multiplayer_game else 0

	# Wire hand CardManagers to PlayerBoards
	player1_board.hand_manager = player1_hand
	player2_board.hand_manager = player2_hand

	# Rearrange layout for client so local player sees their board at bottom
	_arrange_for_local_player()

	if not is_multiplayer_game or NetworkManager.is_host():
		# Host / solo: create and run TurnManager
		turn_manager = TurnManager.new()
		turn_manager.setup(CardData)

		# Connect turn manager signals
		turn_manager.phase_started.connect(_on_phase_started)
		turn_manager.phase_ended.connect(_on_phase_ended)
		turn_manager.awaiting_player_action.connect(_on_awaiting_action)
		turn_manager.turn_started.connect(_on_turn_started)
		turn_manager.game_ended.connect(_on_game_ended)
		turn_manager.log_message.connect(_on_log_message)

		# Connect action handler signals for visual feedback
		turn_manager.action_handler.battle_card_played.connect(_on_battle_card_played)
		turn_manager.action_handler.monster_advanced.connect(_on_monster_advanced)
		turn_manager.action_handler.battle_card_crushed.connect(_on_battle_card_crushed)
		turn_manager.action_handler.counter_succeeded.connect(_on_counter_succeeded)
		turn_manager.action_handler.counter_failed.connect(_on_counter_failed)

		# Connect effect handler signals for player choice UIs
		turn_manager.action_handler.effect_handler.deck_search_requested.connect(_on_deck_search_requested)

		# Connect player state signals so mid-effect changes (e.g. search_deck adding
		# a card to hand) trigger visual updates immediately
		for player in turn_manager.game_state.players:
			player.hand_changed.connect(_on_state_changed)
			player.zones_changed.connect(_on_state_changed)
	else:
		# Client: initialize empty client state, wait for host RPCs
		_client_players = [PlayerState.new(0), PlayerState.new(1)]

	# Connect buttons
	btn_play_battle.pressed.connect(_on_play_battle_pressed)
	btn_play_strategy.pressed.connect(_on_play_strategy_pressed)
	btn_gain_rage.pressed.connect(_on_gain_rage_pressed)
	btn_play_monster.pressed.connect(_on_play_monster_pressed)
	btn_invade.pressed.connect(_on_invade_pressed)
	btn_pass.pressed.connect(_on_pass_pressed)

	# Connect hand drag signals for drag-to-zone
	player1_hand.hand_card_drag_started.connect(_on_hand_drag_started)
	player1_hand.hand_card_drag_ended.connect(_on_hand_drag_ended)
	player2_hand.hand_card_drag_started.connect(_on_hand_drag_started)
	player2_hand.hand_card_drag_ended.connect(_on_hand_drag_ended)

	# Listen for disconnects in multiplayer
	if is_multiplayer_game:
		NetworkManager.player_disconnected.connect(_on_opponent_disconnected)

	# Connect deck search skip button
	deck_search_skip.pressed.connect(_on_deck_search_skip)

	# Hide overlays and prompts
	end_game_panel.visible = false
	card_select_prompt.visible = false
	deck_search_overlay.visible = false

	# Position hands over hand spaces (deferred so layout is resolved)
	call_deferred("_position_hands")

	# Initial board sync and start (host/solo only)
	if turn_manager:
		_sync_boards()
		call_deferred("_start_game")
	else:
		_disable_all_buttons()


func _start_game() -> void:
	turn_manager.start_game()


func _arrange_for_local_player() -> void:
	if local_player_id != 1:
		return

	var vbox := $VBoxContainer

	# Swap hand spaces and boards: local (P2) to bottom, opponent (P1) to top
	vbox.move_child(player2_hand_space, 5)
	vbox.move_child(player1_hand_space, 1)
	vbox.move_child(player1_board, 2)
	vbox.move_child(player2_board, 4)

	# Swap hand space sizes (opponent=small, local=large)
	player1_hand_space.custom_minimum_size.y = 30
	player2_hand_space.custom_minimum_size.y = 100

	# Toggle mirroring (P1 now at top needs mirroring, P2 at bottom doesn't)
	player1_board.toggle_mirrored()
	player2_board.toggle_mirrored()


func _position_hands() -> void:
	var local_hand: Node2D
	var local_space: Control
	var opponent_hand: Node2D
	var opponent_space: Control

	if local_player_id == 0:
		local_hand = player1_hand
		local_space = player1_hand_space
		opponent_hand = player2_hand
		opponent_space = player2_hand_space
	else:
		local_hand = player2_hand
		local_space = player2_hand_space
		opponent_hand = player1_hand
		opponent_space = player1_hand_space

	# Local player hand: visible, centered in hand space
	if local_space and local_hand:
		var rect := local_space.get_global_rect()
		local_hand.global_position = Vector2(rect.position.x + rect.size.x * 0.3, rect.position.y + rect.size.y / 2.0)

	# Opponent hand: mostly off-screen at top edge
	if opponent_space and opponent_hand:
		var rect := opponent_space.get_global_rect()
		opponent_hand.global_position = Vector2(rect.position.x + rect.size.x * 0.3, rect.position.y - 160.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_position_hands")


# --- State access helpers (work for both host and client) ---

func _get_current_pid() -> int:
	if turn_manager:
		return turn_manager.game_state.current_player_id
	return _client_current_player_id


func _get_player_state(pid: int) -> PlayerState:
	if turn_manager:
		return turn_manager.game_state.players[pid]
	return _client_players[pid]


func _get_current_player() -> PlayerState:
	return _get_player_state(_get_current_pid())


func _get_opponent_player() -> PlayerState:
	return _get_player_state(1 - _get_current_pid())


# --- Action submission (routes to TurnManager or RPC) ---

func _submit_action(action: CardEnums.ActionType, params: Dictionary = {}) -> void:
	if not is_multiplayer_game or NetworkManager.is_host():
		turn_manager.submit_action(action, params)
	else:
		var params_json := JSON.stringify(params) if not params.is_empty() else ""
		_rpc_submit_action.rpc_id(1, int(action), params_json)


# --- Signal handlers from TurnManager (host/solo only) ---

func _on_phase_started(phase: CardEnums.GamePhase) -> void:
	phase_label.text = CardEnums.phase_to_string(phase)
	_sync_boards()
	_broadcast_state()


func _on_phase_ended(_phase: CardEnums.GamePhase) -> void:
	_sync_boards()
	_broadcast_state()


func _on_turn_started(player_id: int) -> void:
	turn_label.text = "Turn %d - Player %d" % [turn_manager.game_state.turn_number, player_id + 1]
	_update_hand_visibility(player_id)
	_sync_boards()
	_broadcast_state()


func _on_awaiting_action(valid_actions: Array) -> void:
	_sync_boards()

	if is_multiplayer_game:
		_broadcast_state()
		var active_id := turn_manager.game_state.current_player_id

		# Compute playable indices for the active player
		var playable := _compute_playable_data()
		var actions_json := JSON.stringify(valid_actions)
		var playable_json := JSON.stringify(playable)

		if active_id == local_player_id:
			# Host's turn
			_client_playable = playable
			_update_action_buttons(valid_actions)
		else:
			# Client's turn — send context, disable host buttons
			_disable_all_buttons()
			for peer_id in NetworkManager.peer_player_map:
				if NetworkManager.peer_player_map[peer_id] == active_id:
					_rpc_receive_action_context.rpc_id(peer_id, actions_json, playable_json)
	else:
		_update_action_buttons(valid_actions)


func _on_game_ended(winner_id: int, reason: String) -> void:
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("WinLabel")
	if win_label:
		win_label.text = "Player %d Wins!\n%s" % [winner_id + 1, reason]
	_disable_all_buttons()
	if is_multiplayer_game and NetworkManager.is_host():
		_rpc_receive_game_ended.rpc(winner_id, reason)


func _on_state_changed() -> void:
	_sync_boards()
	_broadcast_state()


func _on_log_message(text: String) -> void:
	if log_output:
		log_output.append_text(text + "\n")
		log_output.scroll_to_line(log_output.get_line_count() - 1)
	if is_multiplayer_game and NetworkManager.is_host():
		_rpc_receive_log.rpc(text)


# --- Action handler visual feedback ---

func _on_battle_card_played(_player_id: int, _card: Dictionary, _zone_index: int) -> void:
	_sync_boards()
	_broadcast_state()


func _on_monster_advanced(_player_id: int, _from_zone: int, _to_zone: int) -> void:
	_sync_boards()
	_broadcast_state()


func _on_battle_card_crushed(player_id: int, zone_index: int, card: Dictionary) -> void:
	_on_log_message("Battle card '%s' crushed in P%d Zone %d!" % [card.get("name", "?"), player_id + 1, zone_index + 1])
	_sync_boards()
	_broadcast_state()


func _on_counter_succeeded(player_id: int, total_cp: int, threat: int) -> void:
	_on_log_message("Counter SUCCESS! P%d CP %d >= Threat %d" % [player_id + 1, total_cp, threat])
	_sync_boards()
	_broadcast_state()


func _on_counter_failed(player_id: int, total_cp: int, threat: int) -> void:
	_on_log_message("Counter failed. P%d CP %d < Threat %d" % [player_id + 1, total_cp, threat])


# --- Button handlers ---

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
	_enter_card_selection("Select a BATTLE card to play:", playable)


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
	_enter_card_selection("Select a STRATEGY card to activate:", playable)


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
	_enter_card_selection("Select a MONSTER card to discard for Rage:", playable)


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
	_enter_card_selection("Select a MONSTER card to play:", playable)


func _on_invade_pressed() -> void:
	if is_multiplayer_game and not NetworkManager.is_local_player_turn(_get_current_pid()):
		return

	var playable: Array[int] = []
	if turn_manager:
		playable = turn_manager.rules_engine.get_discardable_cards_for_invade(turn_manager.game_state.get_current_player())
	else:
		playable.assign(_client_playable.get("invade_cards", []))
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.INVADE
	_enter_card_selection("Select a card to discard for Invasion:", playable)


func _on_pass_pressed() -> void:
	if waiting_for_card_select or waiting_for_zone_select:
		_cancel_selection()
		if turn_manager:
			_update_action_buttons(turn_manager.rules_engine.get_valid_actions(turn_manager.game_state))
		else:
			_update_action_buttons(_client_playable.get("valid_actions", []))
		return
	_cancel_selection()
	_submit_action(CardEnums.ActionType.PASS)


# --- Card selection flow ---

func _enter_card_selection(prompt_text: String, valid_indices: Array[int]) -> void:
	waiting_for_card_select = true
	card_select_prompt.text = prompt_text
	card_select_prompt.visible = true
	_disable_all_buttons()
	btn_pass.disabled = false
	btn_pass.text = "Cancel"

	var board := _get_active_player_board()
	if board and board.hand_manager:
		var visual_indices := _hand_indices_to_visual(valid_indices, board)
		board.hand_manager.enter_selection_mode(visual_indices)
		if not board.hand_manager.card_selected.is_connected(_on_hand_card_selected):
			board.hand_manager.card_selected.connect(_on_hand_card_selected)


func _on_hand_card_selected(card: Control, _visual_index: int) -> void:
	if not waiting_for_card_select:
		return

	selected_card_id = card.card_data.get("id", "") if "card_data" in card else ""
	if selected_card_id.is_empty():
		return

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
	card_select_prompt.text = "Select a ZONE to place the battle card:"

	var valid_zones: Array[int] = []
	if turn_manager:
		var state := turn_manager.game_state
		valid_zones = turn_manager.rules_engine.get_valid_zones_for_battle_card(state.get_current_player(), state.get_opponent_of_current())
	else:
		valid_zones.assign(_client_playable.get("battle_zones", []))

	var board := _get_active_player_board()
	if board:
		board.hand_manager.exit_selection_mode()
		board.highlight_valid_zones(valid_zones)
		for i in range(board.zone_slots.size()):
			var slot: Slot = board.zone_slots[i]
			if i in valid_zones:
				slot.accept_cards = true
				if not slot.card_placed.is_connected(_on_zone_slot_clicked):
					slot.card_placed.connect(_on_zone_slot_clicked.bind(i))
				if not slot.hover_started.is_connected(_on_zone_hover_clicked):
					slot.hover_started.connect(_on_zone_hover_clicked.bind(i))


func _on_zone_slot_clicked(_card: Control, _zone_index: int) -> void:
	pass


func _on_zone_hover_clicked(_zone_index: int) -> void:
	if not waiting_for_zone_select:
		return
	pass


func _input(event: InputEvent) -> void:
	if not waiting_for_zone_select:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var board := _get_active_player_board()
		if not board:
			return

		var mouse_pos := get_global_mouse_position()
		for i in range(board.zone_slots.size()):
			var slot: Slot = board.zone_slots[i]
			var rect := Rect2(slot.global_position, slot.size)
			if rect.has_point(mouse_pos) and slot.is_empty() and slot.is_highlighted:
				var hand_idx: int = _find_hand_index_by_id(selected_card_id)
				_cancel_selection()
				if hand_idx >= 0:
					_submit_action(CardEnums.ActionType.PLAY_BATTLE, {
						"hand_index": hand_idx,
						"zone_index": i
					})
				return


func _cancel_selection() -> void:
	waiting_for_card_select = false
	waiting_for_zone_select = false
	selected_card_id = ""
	card_select_prompt.visible = false
	btn_pass.text = "Pass"

	for board in [player1_board, player2_board]:
		if board and board.hand_manager:
			board.hand_manager.exit_selection_mode()
			if board.hand_manager.card_selected.is_connected(_on_hand_card_selected):
				board.hand_manager.card_selected.disconnect(_on_hand_card_selected)
		if board:
			board.clear_highlights()
			for slot in board.zone_slots:
				if slot.card_placed.is_connected(_on_zone_slot_clicked):
					slot.card_placed.disconnect(_on_zone_slot_clicked)
				if slot.hover_started.is_connected(_on_zone_hover_clicked):
					slot.hover_started.disconnect(_on_zone_hover_clicked)


# --- UI helpers ---

func _sync_boards() -> void:
	if turn_manager and turn_manager.game_state:
		var state := turn_manager.game_state
		if player1_board:
			player1_board.sync_to_state(state.players[0])
		if player2_board:
			player2_board.sync_to_state(state.players[1])
	elif not _client_players.is_empty():
		if player1_board:
			player1_board.sync_to_state(_client_players[0])
		if player2_board:
			player2_board.sync_to_state(_client_players[1])
	call_deferred("_position_hands")


func _update_hand_visibility(active_player_id: int) -> void:
	if is_multiplayer_game:
		# Multiplayer: local player always face-up, opponent always face-down
		if player1_board:
			player1_board.set_hand_face_down(local_player_id != 0)
		if player2_board:
			player2_board.set_hand_face_down(local_player_id != 1)
	else:
		# Solo: active player face-up, opponent face-down
		if player1_board:
			player1_board.set_hand_face_down(active_player_id != 0)
		if player2_board:
			player2_board.set_hand_face_down(active_player_id != 1)


func _update_action_buttons(valid_actions: Array) -> void:
	btn_play_battle.disabled = CardEnums.ActionType.PLAY_BATTLE not in valid_actions
	btn_play_strategy.disabled = CardEnums.ActionType.PLAY_STRATEGY not in valid_actions
	btn_gain_rage.disabled = CardEnums.ActionType.GAIN_RAGE not in valid_actions
	btn_play_monster.disabled = CardEnums.ActionType.PLAY_MONSTER not in valid_actions
	btn_invade.disabled = CardEnums.ActionType.INVADE not in valid_actions
	btn_pass.disabled = false
	btn_pass.text = "Pass"


func _disable_all_buttons() -> void:
	btn_play_battle.disabled = true
	btn_play_strategy.disabled = true
	btn_gain_rage.disabled = true
	btn_play_monster.disabled = true
	btn_invade.disabled = true
	btn_pass.disabled = true


func _get_active_player_board() -> Control:
	var active_id: int = _get_current_pid()
	if active_id == 0:
		return player1_board
	else:
		return player2_board


## Translate player.hand indices to managed_cards indices by matching card IDs
func _hand_indices_to_visual(hand_indices: Array[int], board: Control) -> Array[int]:
	var player := _get_current_player()
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


## Find a card's index in player.hand by its unique ID
func _find_hand_index_by_id(card_id: String) -> int:
	var player := _get_current_player()
	for i in range(player.hand.size()):
		if player.hand[i].get("id") == card_id:
			return i
	return -1


# --- Drag-to-zone ---

func _on_hand_drag_started(card: Control) -> void:
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

	if card_type == CardEnums.CardType.BATTLE:
		var card_id: String = card_data.get("id", "")
		var hand_idx := _find_hand_index_by_id(card_id)
		if hand_idx >= 0:
			var playable_battle: Array[int] = []
			var valid_zones: Array[int] = []
			if turn_manager:
				var opponent := turn_manager.game_state.get_opponent_of_current()
				playable_battle = turn_manager.rules_engine.get_playable_battle_cards(player, opponent)
				valid_zones = turn_manager.rules_engine.get_valid_zones_for_battle_card(player, opponent)
			else:
				playable_battle.assign(_client_playable.get("battle_cards", []))
				valid_zones.assign(_client_playable.get("battle_zones", []))
			if hand_idx in playable_battle:
				_drag_valid_zones = valid_zones
				_drag_action = CardEnums.ActionType.PLAY_BATTLE

	if not _drag_valid_zones.is_empty():
		board.highlight_valid_zones(_drag_valid_zones)


func _on_hand_drag_ended(card: Control) -> void:
	var board := _get_active_player_board()

	if board:
		board.clear_highlights()

	if _drag_card != card or _drag_valid_zones.is_empty():
		_drag_card = null
		_drag_valid_zones = []
		return

	var mouse_pos := get_global_mouse_position()
	if board:
		for i in _drag_valid_zones:
			var slot: Slot = board.zone_slots[i]
			var rect := Rect2(slot.global_position, slot.size)
			if rect.has_point(mouse_pos) and slot.is_empty():
				var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
				var hand_idx := _find_hand_index_by_id(card_id)
				if hand_idx >= 0:
					board.hand_manager.drop_handled = true
					_drag_card = null
					_drag_valid_zones = []
					_submit_action(_drag_action, {
						"hand_index": hand_idx,
						"zone_index": i
					})
					return

	_drag_card = null
	_drag_valid_zones = []


# --- Deck search UI ---

func _on_deck_search_requested(player_id: int, matching_cards: Array[Dictionary], prompt: String) -> void:
	if is_multiplayer_game and player_id != local_player_id:
		# Forward to the remote client who needs to make the choice
		var cards_json := JSON.stringify(matching_cards)
		for peer_id in NetworkManager.peer_player_map:
			if NetworkManager.peer_player_map[peer_id] == player_id:
				_rpc_deck_search_requested.rpc_id(peer_id, cards_json, prompt)
		return
	_show_deck_search(matching_cards, prompt)


func _show_deck_search(cards: Array[Dictionary], prompt: String) -> void:
	# Clear any previous cards from the grid
	for child in deck_search_grid.get_children():
		child.queue_free()

	deck_search_prompt.text = prompt
	deck_search_overlay.visible = true

	# Populate grid with selectable card instances
	for card_data in cards:
		var card: Control = card_scene.instantiate()
		if card.has_method("set_card_data_dict"):
			card.set_card_data_dict(card_data)
		card.is_selectable = true
		card.drag_enabled = false
		card.card_clicked.connect(_on_deck_search_card_clicked)
		deck_search_grid.add_child(card)


func _on_deck_search_card_clicked(card: Control) -> void:
	var selected: Dictionary = card.card_data if "card_data" in card else {}
	_hide_deck_search()
	_resolve_deck_search_local(selected)


func _on_deck_search_skip() -> void:
	_hide_deck_search()
	_resolve_deck_search_local({})


func _hide_deck_search() -> void:
	deck_search_overlay.visible = false
	for child in deck_search_grid.get_children():
		if child.card_clicked.is_connected(_on_deck_search_card_clicked):
			child.card_clicked.disconnect(_on_deck_search_card_clicked)
		child.queue_free()


func _resolve_deck_search_local(selected: Dictionary) -> void:
	if is_multiplayer_game and not NetworkManager.is_host():
		# Client sends selection back to host
		_rpc_deck_search_resolved.rpc_id(1, JSON.stringify(selected))
	else:
		turn_manager.action_handler.effect_handler.resolve_deck_search(selected)


# --- Multiplayer: State broadcast (host -> client) ---

func _broadcast_state() -> void:
	if not is_multiplayer_game or not NetworkManager.is_host():
		return
	if not turn_manager or not turn_manager.game_state:
		return

	for peer_id in NetworkManager.peer_player_map:
		if peer_id == 1:
			continue  # Don't send to self (server peer ID is 1)
		var viewer_id: int = NetworkManager.peer_player_map[peer_id]
		var state_json := _serialize_game_state(viewer_id)
		_rpc_receive_state.rpc_id(peer_id, state_json)


func _serialize_game_state(viewer_id: int) -> String:
	var gs := turn_manager.game_state
	var data := {
		"current_player_id": gs.current_player_id,
		"current_phase": int(gs.current_phase),
		"turn_number": gs.turn_number,
		"is_game_over": turn_manager.is_game_over,
		"players": []
	}
	for i in range(2):
		var pd := _serialize_player_state(gs.players[i])
		if i != viewer_id:
			# Strip hand data for opponent — only send count
			pd.erase("hand")
		data["players"].append(pd)
	return JSON.stringify(data)


func _serialize_player_state(ps: PlayerState) -> Dictionary:
	return {
		"player_id": ps.player_id,
		"monster_zone": ps.monster_zone,
		"rage": ps.rage,
		"current_monster": ps.current_monster,
		"zones": ps.zones.duplicate(true),
		"strategy_zones": ps.strategy_zones.duplicate(true),
		"hand": ps.hand.duplicate(true),
		"hand_count": ps.hand.size(),
		"main_deck_count": ps.main_deck.size(),
		"discard_pile_count": ps.discard_pile.size(),
		"has_invaded_this_turn": ps.has_invaded_this_turn,
		"burst_monster": ps.burst_monster,
		"pre_burst_monster": ps.pre_burst_monster,
	}


func _compute_playable_data() -> Dictionary:
	var gs := turn_manager.game_state
	var player := gs.get_current_player()
	var opponent := gs.get_opponent_of_current()
	var rules := turn_manager.rules_engine
	return {
		"valid_actions": rules.get_valid_actions(gs),
		"battle_cards": rules.get_playable_battle_cards(player, opponent),
		"battle_zones": rules.get_valid_zones_for_battle_card(player, opponent),
		"strategy_cards": rules.get_playable_strategy_cards(player),
		"monster_cards": rules.get_playable_monsters(player),
		"rage_cards": rules.get_monster_cards_for_rage(player),
		"invade_cards": rules.get_discardable_cards_for_invade(player),
	}


# --- Multiplayer RPCs ---

## Client -> Host: submit an action
@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_action(action_type: int, params_json: String) -> void:
	if not NetworkManager.is_host() or not turn_manager:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var sender_player_id: int = NetworkManager.peer_player_map.get(sender_id, -1)
	if sender_player_id != turn_manager.game_state.current_player_id:
		return  # Not their turn

	var action: CardEnums.ActionType = action_type as CardEnums.ActionType
	var params: Dictionary = {}
	if not params_json.is_empty():
		params = JSON.parse_string(params_json)
		# JSON parses ints as floats — convert known fields
		if params.has("hand_index"):
			params["hand_index"] = int(params["hand_index"])
		if params.has("zone_index"):
			params["zone_index"] = int(params["zone_index"])

	turn_manager.submit_action(action, params)


## Host -> Client: full game state update
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_state(state_json: String) -> void:
	var data: Dictionary = JSON.parse_string(state_json)
	if data.is_empty():
		return

	_client_current_player_id = int(data["current_player_id"])

	# Reconstruct PlayerState objects
	var players_data: Array = data["players"]
	for i in range(2):
		var pd: Dictionary = players_data[i]
		_client_players[i] = _dict_to_player_state(pd, i == local_player_id)

	# Update UI
	phase_label.text = CardEnums.phase_to_string(int(data["current_phase"]) as CardEnums.GamePhase)
	turn_label.text = "Turn %d - Player %d" % [int(data["turn_number"]), int(data["current_player_id"]) + 1]
	_update_hand_visibility(_client_current_player_id)
	_sync_boards()


## Host -> Client: valid actions and playable indices
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_action_context(actions_json: String, playable_json: String) -> void:
	var actions: Array = JSON.parse_string(actions_json)
	_client_playable = JSON.parse_string(playable_json)
	# Store valid_actions in playable for _on_pass_pressed cancel path
	_client_playable["valid_actions"] = actions
	# Convert float arrays to int arrays
	for key in _client_playable:
		if _client_playable[key] is Array:
			var arr: Array = _client_playable[key]
			for j in range(arr.size()):
				if arr[j] is float:
					arr[j] = int(arr[j])
	_update_action_buttons(actions)


## Host -> Client: log message
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_log(text: String) -> void:
	if log_output:
		log_output.append_text(text + "\n")
		log_output.scroll_to_line(log_output.get_line_count() - 1)


## Host -> Client: deck search request (player must choose a card)
@rpc("authority", "call_remote", "reliable")
func _rpc_deck_search_requested(cards_json: String, prompt: String) -> void:
	var cards: Array = JSON.parse_string(cards_json)
	var typed_cards: Array[Dictionary] = []
	for c in cards:
		typed_cards.append(c)
	_show_deck_search(typed_cards, prompt)


## Client -> Host: deck search resolved (player chose a card or skipped)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_deck_search_resolved(selected_json: String) -> void:
	if not NetworkManager.is_host() or not turn_manager:
		return
	var selected: Dictionary = {}
	if not selected_json.is_empty():
		selected = JSON.parse_string(selected_json)
		if selected == null:
			selected = {}
	turn_manager.action_handler.effect_handler.resolve_deck_search(selected)


## Host -> Client: game over
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_game_ended(winner_id: int, reason: String) -> void:
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("WinLabel")
	if win_label:
		win_label.text = "Player %d Wins!\n%s" % [winner_id + 1, reason]
	_disable_all_buttons()


# --- Multiplayer: State deserialization (client) ---

func _dict_to_player_state(data: Dictionary, is_local: bool) -> PlayerState:
	var ps := PlayerState.new(int(data["player_id"]))
	ps.monster_zone = int(data["monster_zone"])
	ps.rage = int(data["rage"])
	ps.current_monster = data.get("current_monster", {})
	ps.has_invaded_this_turn = data.get("has_invaded_this_turn", false)
	ps.burst_monster = data.get("burst_monster", {})
	ps.pre_burst_monster = data.get("pre_burst_monster", {})

	# Zones
	var zones_data: Array = data.get("zones", [])
	for i in range(mini(zones_data.size(), 8)):
		ps.zones[i] = zones_data[i]

	# Strategy zones
	var sz_data: Array = data.get("strategy_zones", [])
	for i in range(mini(sz_data.size(), 2)):
		ps.strategy_zones[i] = sz_data[i]

	# Hand: full data for local player, face-down placeholders for opponent
	if is_local and data.has("hand"):
		ps.hand.assign(data["hand"])
	else:
		var count: int = int(data.get("hand_count", 0))
		ps.hand.clear()
		for j in range(count):
			ps.hand.append({"face_down": true, "id": "opponent_%d" % j})

	# Deck/discard: only counts needed for display labels
	var deck_count: int = int(data.get("main_deck_count", 0))
	ps.main_deck.resize(deck_count)
	for j in range(deck_count):
		ps.main_deck[j] = {}

	var discard_count: int = int(data.get("discard_pile_count", 0))
	ps.discard_pile.resize(discard_count)
	for j in range(discard_count):
		ps.discard_pile[j] = {}

	return ps


# --- Multiplayer: Disconnect handling ---

func _on_opponent_disconnected(_peer_id: int) -> void:
	_disable_all_buttons()
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("WinLabel")
	if win_label:
		win_label.text = "Opponent disconnected."
	# The EndGamePanel should have a way to return to menu.
	# If it has a button, it will handle it. Otherwise we add a timer.
