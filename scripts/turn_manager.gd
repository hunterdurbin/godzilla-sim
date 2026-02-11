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
var effect_handler: EffectHandler
var is_game_over: bool = false
var _processing_action: bool = false
var _waiting_for_input: bool = false


func setup(card_data_node: Node) -> void:
	game_state = GameState.new()
	rules_engine = RulesEngine.new()
	action_handler = ActionHandler.new()
	effect_handler = EffectHandler.new()
	effect_handler.setup(game_state)
	effect_handler.action_handler = action_handler
	action_handler.effect_handler = effect_handler
	rules_engine.effect_handler = effect_handler

	# Set up each player's deck (per-player selection or fallback)
	for i in range(2):
		var player := game_state.players[i]
		if DecklistManager.has_player_deck(i):
			player.monster_deck = DecklistManager.get_player_monster_deck(i).duplicate(true)
			player.main_deck = DecklistManager.build_main_deck_for_player(i)
		else:
			player.monster_deck = card_data_node.get_monster_deck(CardEnums.CardTrait.GODZILLA)
			player.main_deck = card_data_node.get_main_deck(i)
		player.main_deck.shuffle()

	# Place Rank I monsters as invading monsters at zone 1
	for player in game_state.players:
		for m in player.monster_deck:
			if m.get("rank") == 1:
				player.current_monster = m
				break
		player.monster_zone = player.current_monster.get("start_zone", 1)
		player.rage = 0

	# Draw 5 cards each
	for player in game_state.players:
		player.draw_cards(5)

	# Connect game over signal
	game_state.game_over.connect(_on_game_over)

	# Recheck valid actions when hand changes during main phase
	for player in game_state.players:
		player.hand_changed.connect(_on_hand_changed)

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

	await _execute_start_phase()


func _execute_start_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.START
	phase_started.emit(CardEnums.GamePhase.START)
	await effect_handler.trigger_phase_start(CardEnums.GamePhase.START)
	await action_handler.resolve_check_timing(game_state) # 7.2.1

	var player := game_state.get_current_player()
	var opponent := game_state.get_opponent_of_current()

	log_message.emit("Start Phase: Drawing %d card(s)" % opponent.get_monster_rank())

	action_handler.execute_start_phase(game_state)

	log_message.emit("Hand size: %d" % player.hand.size())

	await action_handler.resolve_check_timing(game_state) # 7.2.5
	await effect_handler.trigger_phase_end(CardEnums.GamePhase.START)
	phase_ended.emit(CardEnums.GamePhase.START)
	_begin_main_phase()


func _begin_main_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.MAIN
	phase_started.emit(CardEnums.GamePhase.MAIN)
	await effect_handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
	await action_handler.resolve_check_timing(game_state) # 7.3.1

	log_message.emit("Main Phase: Choose your actions")

	_processing_action = false
	_prompt_player_actions()


func _prompt_player_actions() -> void:
	if is_game_over:
		return

	_waiting_for_input = true
	var valid_actions := rules_engine.get_valid_actions(game_state)
	awaiting_player_action.emit(valid_actions)


func submit_action(action: CardEnums.ActionType, params: Dictionary = {}) -> void:
	if is_game_over or _processing_action:
		return
	_waiting_for_input = false
	_processing_action = true

	if action == CardEnums.ActionType.PASS:
		log_message.emit("Player %d passes." % (game_state.current_player_id + 1))
		await effect_handler.trigger_phase_end(CardEnums.GamePhase.MAIN)
		phase_ended.emit(CardEnums.GamePhase.MAIN)
		# Keep _processing_action = true through automated phases (COUNTER → END → START)
		# to block any submit_action calls until the next MAIN phase is ready for input.
		_begin_counter_phase()
		return

	# Capture card info before execute pops it from hand
	var player := game_state.get_current_player()
	var player_name := "Player %d" % (game_state.current_player_id + 1)
	var hand_index: int = params.get("hand_index", -1)
	var card_number: String = ""
	if hand_index >= 0 and hand_index < player.hand.size():
		var card_id: String = player.hand[hand_index].get("id", "")
		# Strip deck/copy suffix: "EBP01-001_0_1" -> "EBP01-001"
		var underscore_pos := card_id.find("_")
		card_number = card_id.substr(0, underscore_pos) if underscore_pos != -1 else card_id

	# Execute the action (may await player choices from effects)
	await action_handler.execute(action, params, game_state)
	await action_handler.resolve_check_timing(game_state) # 10.4.4.1

	# Log the action
	var card_link := "[url=%s][%s][/url]" % [card_number, card_number] if not card_number.is_empty() else ""
	match action:
		CardEnums.ActionType.PLAY_BATTLE:
			log_message.emit("%s: Played %s to Zone %d" % [player_name, card_link, params.get("zone_index", 0) + 1])
		CardEnums.ActionType.PLAY_STRATEGY:
			log_message.emit("%s: Played %s to Strategy Zone" % [player_name, card_link])
		CardEnums.ActionType.GAIN_RAGE:
			log_message.emit("%s: Gained rage (now %d) (discarded %s)" % [player_name, game_state.get_current_player().rage, card_link])
		CardEnums.ActionType.PLAY_MONSTER:
			log_message.emit("%s: Played %s as Monster (rage now %d)" % [player_name, card_link, game_state.get_current_player().rage])
		CardEnums.ActionType.INVADE:
			log_message.emit("%s: Invaded! Monster now at zone %d (discarded %s)" % [player_name, game_state.get_current_player().monster_zone, card_link])

	_processing_action = false

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
	await effect_handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	await action_handler.resolve_check_timing(game_state) # 7.4.1

	var player := game_state.get_current_player()
	var opponent := game_state.get_opponent_of_current()
	var total_cp: int = player.get_total_counter_power()
	var threat: int = opponent.get_threat_level()

	log_message.emit("Counter Phase: CP %d vs Threat %d" % [total_cp, threat])

	await action_handler.resolve_counter(game_state)

	if is_game_over:
		return

	await action_handler.resolve_check_timing(game_state) # 7.4.4
	await effect_handler.trigger_phase_end(CardEnums.GamePhase.COUNTER)
	phase_ended.emit(CardEnums.GamePhase.COUNTER)
	_begin_end_phase()


func _begin_end_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.END
	phase_started.emit(CardEnums.GamePhase.END)
	await effect_handler.trigger_phase_start(CardEnums.GamePhase.END)
	await action_handler.resolve_check_timing(game_state) # 7.5.1

	var player := game_state.get_current_player()
	log_message.emit("End Phase: Monster at zone %d" % player.monster_zone)

	# Burst discard, then advance (7.5.2)
	await action_handler.execute_end_phase_burst_discard(game_state)
	await action_handler.execute_end_phase_advance(game_state)

	# Check win from end-phase advance
	if is_game_over:
		return

	var winner := rules_engine.check_win_condition(game_state)
	if winner >= 0:
		_on_game_over(winner, "Victory through invasion!")
		return

	await action_handler.resolve_check_timing(game_state) # 7.5.3

	# Draw up to 5 cards (7.5.4)
	action_handler.execute_end_phase_draw(game_state)
	log_message.emit("Hand refilled to %d cards" % player.hand.size())

	await action_handler.resolve_check_timing(game_state) # 7.5.5

	await effect_handler.trigger_phase_end(CardEnums.GamePhase.END)
	phase_ended.emit(CardEnums.GamePhase.END)
	turn_ended.emit(game_state.current_player_id)

	# Switch turns
	_begin_turn(1 - game_state.current_player_id)


func _on_hand_changed() -> void:
	if _waiting_for_input and not _processing_action:
		_prompt_player_actions()


func _on_game_over(winner_id: int, reason: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	log_message.emit("GAME OVER! Player %d wins: %s" % [winner_id + 1, reason])
	game_ended.emit(winner_id, reason)
