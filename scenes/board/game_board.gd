extends Control

## Main game controller. Orchestrates the UI, TurnManager, and both PlayerBoards.

var turn_manager: TurnManager
var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")

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

# State tracking
var pending_action: CardEnums.ActionType = CardEnums.ActionType.PASS
var waiting_for_card_select: bool = false
var waiting_for_zone_select: bool = false
var selected_hand_index: int = -1


func _ready() -> void:
	# Initialize the turn manager
	turn_manager = TurnManager.new()
	turn_manager.setup(CardData)

	# Wire hand CardManagers to PlayerBoards
	player1_board.hand_manager = player1_hand
	player2_board.hand_manager = player2_hand

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

	# Connect buttons
	btn_play_battle.pressed.connect(_on_play_battle_pressed)
	btn_play_strategy.pressed.connect(_on_play_strategy_pressed)
	btn_gain_rage.pressed.connect(_on_gain_rage_pressed)
	btn_play_monster.pressed.connect(_on_play_monster_pressed)
	btn_invade.pressed.connect(_on_invade_pressed)
	btn_pass.pressed.connect(_on_pass_pressed)

	# Hide end game panel and card select prompt
	end_game_panel.visible = false
	card_select_prompt.visible = false

	# Position hands over hand spaces (deferred so layout is resolved)
	call_deferred("_position_hands")

	# Initial board sync
	_sync_boards()

	# Start the game (deferred to let scene tree finish setup)
	call_deferred("_start_game")


func _start_game() -> void:
	turn_manager.start_game()


func _position_hands() -> void:
	# Player 1 hand: left side, vertically centered in hand space
	if player1_hand_space and player1_hand:
		var rect := player1_hand_space.get_global_rect()
		player1_hand.global_position = Vector2(rect.position.x + rect.size.x * 0.3, rect.position.y + rect.size.y / 2.0)
	# Player 2 (opponent) hand: left side, mostly off-screen at top edge
	if player2_hand_space and player2_hand:
		var rect := player2_hand_space.get_global_rect()
		player2_hand.global_position = Vector2(rect.position.x + rect.size.x * 0.3, rect.position.y - 160.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_position_hands")


# --- Signal handlers from TurnManager ---

func _on_phase_started(phase: CardEnums.GamePhase) -> void:
	phase_label.text = CardEnums.phase_to_string(phase)
	_sync_boards()


func _on_phase_ended(_phase: CardEnums.GamePhase) -> void:
	_sync_boards()


func _on_turn_started(player_id: int) -> void:
	turn_label.text = "Turn %d - Player %d" % [turn_manager.game_state.turn_number, player_id + 1]

	# Show/hide hands based on whose turn it is
	_update_hand_visibility(player_id)
	_sync_boards()


func _on_awaiting_action(valid_actions: Array) -> void:
	_sync_boards()
	_update_action_buttons(valid_actions)


func _on_game_ended(winner_id: int, reason: String) -> void:
	end_game_panel.visible = true
	var win_label: Label = end_game_panel.get_node_or_null("WinLabel")
	if win_label:
		win_label.text = "Player %d Wins!\n%s" % [winner_id + 1, reason]
	_disable_all_buttons()


func _on_log_message(text: String) -> void:
	if log_output:
		log_output.append_text(text + "\n")
		# Auto-scroll to bottom
		log_output.scroll_to_line(log_output.get_line_count() - 1)


# --- Action handler visual feedback ---

func _on_battle_card_played(_player_id: int, _card: Dictionary, _zone_index: int) -> void:
	_sync_boards()


func _on_monster_advanced(_player_id: int, _from_zone: int, _to_zone: int) -> void:
	_sync_boards()


func _on_battle_card_crushed(player_id: int, zone_index: int, card: Dictionary) -> void:
	_on_log_message("Battle card '%s' crushed in P%d Zone %d!" % [card.get("name", "?"), player_id + 1, zone_index + 1])
	_sync_boards()


func _on_counter_succeeded(player_id: int, total_cp: int, threat: int) -> void:
	_on_log_message("Counter SUCCESS! P%d CP %d >= Threat %d" % [player_id + 1, total_cp, threat])
	_sync_boards()


func _on_counter_failed(player_id: int, total_cp: int, threat: int) -> void:
	_on_log_message("Counter failed. P%d CP %d < Threat %d" % [player_id + 1, total_cp, threat])


# --- Button handlers ---

func _on_play_battle_pressed() -> void:
	var state := turn_manager.game_state
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()
	var rules := turn_manager.rules_engine

	var playable := rules.get_playable_battle_cards(player, opponent)
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.PLAY_BATTLE
	_enter_card_selection("Select a BATTLE card to play:", playable)


func _on_play_strategy_pressed() -> void:
	var state := turn_manager.game_state
	var player := state.get_current_player()
	var rules := turn_manager.rules_engine

	var playable := rules.get_playable_strategy_cards(player)
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.PLAY_STRATEGY
	_enter_card_selection("Select a STRATEGY card to activate:", playable)


func _on_gain_rage_pressed() -> void:
	var state := turn_manager.game_state
	var player := state.get_current_player()
	var rules := turn_manager.rules_engine

	var discardable := rules.get_monster_cards_for_rage(player)
	if discardable.is_empty():
		return

	pending_action = CardEnums.ActionType.GAIN_RAGE
	_enter_card_selection("Select a MONSTER card to discard for Rage:", discardable)


func _on_play_monster_pressed() -> void:
	var state := turn_manager.game_state
	var player := state.get_current_player()
	var rules := turn_manager.rules_engine

	var playable := rules.get_playable_monsters(player)
	if playable.is_empty():
		return

	pending_action = CardEnums.ActionType.PLAY_MONSTER
	_enter_card_selection("Select a MONSTER card to play:", playable)


func _on_invade_pressed() -> void:
	var state := turn_manager.game_state
	var player := state.get_current_player()
	var rules := turn_manager.rules_engine

	var discardable := rules.get_discardable_cards_for_invade(player)
	if discardable.is_empty():
		return

	pending_action = CardEnums.ActionType.INVADE
	_enter_card_selection("Select a card to discard for Invasion:", discardable)


func _on_pass_pressed() -> void:
	_cancel_selection()
	turn_manager.submit_action(CardEnums.ActionType.PASS)


# --- Card selection flow ---

func _enter_card_selection(prompt_text: String, valid_indices: Array[int]) -> void:
	waiting_for_card_select = true
	card_select_prompt.text = prompt_text
	card_select_prompt.visible = true
	_disable_all_buttons()
	btn_pass.disabled = false
	btn_pass.text = "Cancel"

	# Enable selection mode on the active player's hand
	var board := _get_active_player_board()
	if board and board.hand_manager:
		board.hand_manager.enter_selection_mode(valid_indices)
		if not board.hand_manager.card_selected.is_connected(_on_hand_card_selected):
			board.hand_manager.card_selected.connect(_on_hand_card_selected)


func _on_hand_card_selected(_card: Control, index: int) -> void:
	if not waiting_for_card_select:
		return

	selected_hand_index = index

	match pending_action:
		CardEnums.ActionType.PLAY_BATTLE:
			# Now need to select a zone
			_enter_zone_selection()
		CardEnums.ActionType.PLAY_STRATEGY:
			_cancel_selection()
			turn_manager.submit_action(CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": index})
		CardEnums.ActionType.GAIN_RAGE:
			_cancel_selection()
			turn_manager.submit_action(CardEnums.ActionType.GAIN_RAGE, {"hand_index": index})
		CardEnums.ActionType.PLAY_MONSTER:
			_cancel_selection()
			turn_manager.submit_action(CardEnums.ActionType.PLAY_MONSTER, {"hand_index": index})
		CardEnums.ActionType.INVADE:
			_cancel_selection()
			turn_manager.submit_action(CardEnums.ActionType.INVADE, {"hand_index": index})


func _enter_zone_selection() -> void:
	waiting_for_card_select = false
	waiting_for_zone_select = true
	card_select_prompt.text = "Select a ZONE to place the battle card:"

	var state := turn_manager.game_state
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()
	var rules := turn_manager.rules_engine
	var valid_zones := rules.get_valid_zones_for_battle_card(player, opponent)

	# Highlight valid zones and connect click signals
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
				# Use mouse_entered for click detection on empty slots
				if not slot.hover_started.is_connected(_on_zone_hover_clicked):
					slot.hover_started.connect(_on_zone_hover_clicked.bind(i))


func _on_zone_slot_clicked(_card: Control, _zone_index: int) -> void:
	# This shouldn't normally fire during selection mode
	pass


func _on_zone_hover_clicked(_zone_index: int) -> void:
	if not waiting_for_zone_select:
		return
	# Use input detection instead
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
				_cancel_selection()
				turn_manager.submit_action(CardEnums.ActionType.PLAY_BATTLE, {
					"hand_index": selected_hand_index,
					"zone_index": i
				})
				return


func _cancel_selection() -> void:
	waiting_for_card_select = false
	waiting_for_zone_select = false
	selected_hand_index = -1
	card_select_prompt.visible = false
	btn_pass.text = "Pass"

	# Exit selection mode on both boards
	for board in [player1_board, player2_board]:
		if board and board.hand_manager:
			board.hand_manager.exit_selection_mode()
			if board.hand_manager.card_selected.is_connected(_on_hand_card_selected):
				board.hand_manager.card_selected.disconnect(_on_hand_card_selected)
		if board:
			board.clear_highlights()
			# Disconnect zone signals
			for slot in board.zone_slots:
				if slot.card_placed.is_connected(_on_zone_slot_clicked):
					slot.card_placed.disconnect(_on_zone_slot_clicked)
				if slot.hover_started.is_connected(_on_zone_hover_clicked):
					slot.hover_started.disconnect(_on_zone_hover_clicked)


# --- UI helpers ---

func _sync_boards() -> void:
	if not turn_manager or not turn_manager.game_state:
		return
	var state := turn_manager.game_state
	if player1_board:
		player1_board.sync_to_state(state.players[0])
	if player2_board:
		player2_board.sync_to_state(state.players[1])
	# Reposition hands in case layout shifted
	call_deferred("_position_hands")


func _update_hand_visibility(active_player_id: int) -> void:
	# Active player sees their hand face-up; opponent's hand is face-down
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
	var active_id: int = turn_manager.game_state.current_player_id
	if active_id == 0:
		return player1_board
	else:
		return player2_board
