class_name TurnManager
extends RefCounted

## Core state machine driving the Godzilla TCG game loop.

signal phase_started(phase: CardEnums.GamePhase)
signal phase_ended(phase: CardEnums.GamePhase)
signal awaiting_player_action(valid_actions: Array)
signal turn_started(player_id: int)
signal turn_ended(player_id: int)
signal game_started()
signal game_ended(winner_id: int, reason: String)
signal log_message(text: String)

var game_state: GameState
var rules_engine: RulesEngine
var action_handler: ActionHandler
var is_game_over: bool = false


func setup(card_data_node: Node) -> void:
	game_state = GameState.new()
	rules_engine = RulesEngine.new()
	action_handler = ActionHandler.new()

	var use_custom_deck := DecklistManager.selected_deck_name != ""

	# Set up Player 1
	var p1 := game_state.players[0]
	if use_custom_deck:
		p1.monster_deck = DecklistManager.selected_monster_deck.duplicate(true)
		p1.main_deck = DecklistManager.build_main_deck_for_player(0)
	else:
		p1.monster_deck = card_data_node.get_monster_deck(CardEnums.CardTrait.GODZILLA)
		p1.main_deck = card_data_node.get_main_deck(0)
	p1.main_deck.shuffle()

	# Set up Player 2
	var p2 := game_state.players[1]
	if use_custom_deck:
		p2.monster_deck = DecklistManager.selected_monster_deck.duplicate(true)
		p2.main_deck = DecklistManager.build_main_deck_for_player(1)
	else:
		p2.monster_deck = card_data_node.get_monster_deck(CardEnums.CardTrait.GODZILLA)
		p2.main_deck = card_data_node.get_main_deck(1)
	p2.main_deck.shuffle()

	# Place Rank I monsters as invading monsters at zone 1
	for player in game_state.players:
		for m in player.monster_deck:
			if m.get("rank") == 1:
				player.current_monster = m
				break
		player.monster_zone = 1
		player.rage = 0

	# Draw 5 cards each
	for player in game_state.players:
		player.draw_cards(5)

	# Connect game over signal
	game_state.game_over.connect(_on_game_over)

	game_started.emit()


func start_game() -> void:
	_begin_turn(0)


func _begin_turn(player_id: int) -> void:
	if is_game_over:
		return

	game_state.current_player_id = player_id
	game_state.turn_number += 1

	log_message.emit("--- Turn %d: Player %d ---" % [game_state.turn_number, player_id + 1])
	turn_started.emit(player_id)

	_execute_start_phase()


func _execute_start_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.START
	phase_started.emit(CardEnums.GamePhase.START)

	var player := game_state.get_current_player()
	var opponent := game_state.get_opponent_of_current()

	log_message.emit("Start Phase: Drawing %d card(s)" % opponent.get_monster_rank())

	action_handler.execute_start_phase(game_state)

	log_message.emit("Hand size: %d" % player.hand.size())

	phase_ended.emit(CardEnums.GamePhase.START)
	_begin_main_phase()


func _begin_main_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.MAIN
	phase_started.emit(CardEnums.GamePhase.MAIN)

	log_message.emit("Main Phase: Choose your actions")

	_prompt_player_actions()


func _prompt_player_actions() -> void:
	if is_game_over:
		return

	var valid_actions := rules_engine.get_valid_actions(game_state)
	awaiting_player_action.emit(valid_actions)


func submit_action(action: CardEnums.ActionType, params: Dictionary = {}) -> void:
	if is_game_over:
		return

	if action == CardEnums.ActionType.PASS:
		log_message.emit("Player %d passes." % (game_state.current_player_id + 1))
		phase_ended.emit(CardEnums.GamePhase.MAIN)
		_begin_counter_phase()
		return

	# Execute the action
	action_handler.execute(action, params, game_state)

	# Log the action
	match action:
		CardEnums.ActionType.PLAY_BATTLE:
			log_message.emit("Played battle card to zone %d" % (params.get("zone_index", 0) + 1))
		CardEnums.ActionType.PLAY_STRATEGY:
			log_message.emit("Activated a strategy card")
		CardEnums.ActionType.GAIN_RAGE:
			log_message.emit("Gained rage (now %d)" % game_state.get_current_player().rage)
		CardEnums.ActionType.PLAY_MONSTER:
			log_message.emit("Played a monster card (rage now %d)" % game_state.get_current_player().rage)
		CardEnums.ActionType.INVADE:
			log_message.emit("Invaded! Monster now at zone %d" % game_state.get_current_player().monster_zone)

	# Check for win condition after each action
	if is_game_over:
		return

	var winner := rules_engine.check_win_condition(game_state)
	if winner >= 0:
		_on_game_over(winner, "Victory through invasion!")
		return

	# Loop back for more actions
	_prompt_player_actions()


func _begin_counter_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.COUNTER
	phase_started.emit(CardEnums.GamePhase.COUNTER)

	var player := game_state.get_current_player()
	var opponent := game_state.get_opponent_of_current()
	var total_cp: int = player.get_total_counter_power()
	var threat: int = opponent.get_threat_level()

	log_message.emit("Counter Phase: CP %d vs Threat %d" % [total_cp, threat])

	action_handler.resolve_counter(game_state)

	if is_game_over:
		return

	phase_ended.emit(CardEnums.GamePhase.COUNTER)
	_begin_end_phase()


func _begin_end_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.END
	phase_started.emit(CardEnums.GamePhase.END)

	var player := game_state.get_current_player()
	log_message.emit("End Phase: Monster at zone %d" % player.monster_zone)

	action_handler.execute_end_phase(game_state)

	# Check win from end-phase advance
	if is_game_over:
		return

	var winner := rules_engine.check_win_condition(game_state)
	if winner >= 0:
		_on_game_over(winner, "Victory through invasion!")
		return

	log_message.emit("Hand refilled to %d cards" % player.hand.size())

	phase_ended.emit(CardEnums.GamePhase.END)
	turn_ended.emit(game_state.current_player_id)

	# Switch turns
	_begin_turn(1 - game_state.current_player_id)


func _on_game_over(winner_id: int, reason: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	log_message.emit("GAME OVER! Player %d wins: %s" % [winner_id + 1, reason])
	game_ended.emit(winner_id, reason)
