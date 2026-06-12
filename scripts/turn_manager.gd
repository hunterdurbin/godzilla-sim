class_name TurnManager
extends RefCounted

## Core state machine driving the Godzilla TCG game loop.

signal phase_started(phase: CardEnums.GamePhase)
signal phase_ended(phase: CardEnums.GamePhase)
signal sub_phase_changed(sub_index: int)
signal awaiting_player_action(valid_actions: Array)
signal turn_started(player_id: int)
signal turn_ended(player_id: int)
signal game_started()
signal game_ended(winner_id: int, reason_key: String)
signal log_message(token: Dictionary)
signal confirmation_requested(prompt: String, setting: String)

var game_state: GameState
var rules_engine: RulesEngine
var action_handler: ActionHandler
var effect_handler: EffectHandler
var session_config: SessionConfig
var is_game_over: bool = false
var _processing_action: bool = false
var _waiting_for_input: bool = false
var _confirmation_pending: bool = false


func confirm() -> void:
	_confirmation_pending = false


func _await_confirmation(prompt: String, setting: String) -> void:
	_confirmation_pending = true
	confirmation_requested.emit(prompt, setting)
	while _confirmation_pending:
		await Engine.get_main_loop().process_frame


func setup(card_data_node: Node, config: SessionConfig = null) -> void:
	session_config = config if config else SessionConfig.from_singletons()
	game_state = GameState.new()
	rules_engine = RulesEngine.new()
	action_handler = ActionHandler.new()
	effect_handler = EffectHandler.new()
	effect_handler.setup(game_state)
	effect_handler.action_handler = action_handler
	action_handler.effect_handler = effect_handler
	rules_engine.effect_handler = effect_handler

	for i in range(2):
		game_state.player_names[i] = str(session_config.player_names[i])

	# Set up each player's deck (per-player selection or fallback)
	for i in range(2):
		var player := game_state.players[i]
		var deck: Dictionary = session_config.decks[i]
		if not deck.is_empty():
			player.monster_deck = deck["monster_deck"].duplicate(true)
			player.main_deck = deck["main_deck"].duplicate(true)
		else:
			player.monster_deck = card_data_node.get_monster_deck(CardEnums.CardTrait.GODZILLA)
			player.main_deck = card_data_node.get_main_deck(i)
		player.main_deck.shuffle()

	# Apply per-format card printing (e.g. Rumble East uses the JP traits). Resolved
	# here, per-match, because the active format isn't known when decks are built.
	var printing := CardData.printing_for_mode(session_config.game_mode)
	for player in game_state.players:
		for c in player.monster_deck:
			CardData.apply_printing(c, printing)
		for c in player.main_deck:
			CardData.apply_printing(c, printing)

	# Place Rank I monsters as invading monsters at zone 1
	for player in game_state.players:
		for m in player.monster_deck:
			if m.get("rank") == 1:
				player.current_monster = m
				player.monster_deck.erase(m)
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


func setup_from_save(data: Dictionary) -> void:
	## Restore a game from a saved state dictionary.
	game_state = GameState.new()
	rules_engine = RulesEngine.new()
	action_handler = ActionHandler.new()
	effect_handler = EffectHandler.new()
	effect_handler.setup(game_state)
	effect_handler.action_handler = action_handler
	action_handler.effect_handler = effect_handler
	rules_engine.effect_handler = effect_handler

	# Restore game-level state
	game_state.turn_number = data.get("turn_number", 1) - 1  # Will be incremented by _begin_turn or resume_to_main_phase
	game_state.current_player_id = data.get("current_player_id", 0)
	game_state.current_phase = data.get("current_phase", CardEnums.GamePhase.START) as CardEnums.GamePhase
	game_state.current_sub_phase = data.get("current_sub_phase", 0)
	var pn: Array = data.get("player_names", ["Player 1", "Player 2"])
	game_state.player_names = [str(pn[0]) if pn.size() > 0 else "Player 1", str(pn[1]) if pn.size() > 1 else "Player 2"]

	# Restore player states
	var players_data: Array = data.get("players", [])
	for i in range(2):
		if i < players_data.size():
			game_state.players[i] = GameSerializer.deserialize_to_player_state(players_data[i])

	# Register effects for all cards currently on the field
	for player in game_state.players:
		for zone_stack in player.zones:
			for card in zone_stack:
				effect_handler.get_effect(card)
		for strat in player.strategy_zones:
			if strat is Dictionary and not strat.is_empty():
				effect_handler.get_effect(strat)
		if not player.current_monster.is_empty():
			effect_handler.get_effect(player.current_monster)

	# Connect signals
	game_state.game_over.connect(_on_game_over)
	for player in game_state.players:
		player.hand_changed.connect(_on_hand_changed)

	game_started.emit()


func start_game(first_player_id: int = 0) -> void:
	_begin_turn(first_player_id)


func resume_to_main_phase(player_id: int, resolve_effects: bool = false) -> void:
	## Resume a loaded game into the main phase.
	## When resolve_effects is true, runs trigger_phase_start and
	## resolve_check_timing before prompting (snapshot was before main-phase
	## effects fired).  When false, skips straight to the player action prompt.
	game_state.current_player_id = player_id
	game_state.turn_number += 1  # Was decremented by 1 in setup_from_save
	game_state.current_phase = CardEnums.GamePhase.MAIN

	log_message.emit(GameLog.turn_start(game_state.turn_number, player_id))
	turn_started.emit(player_id)
	phase_started.emit(CardEnums.GamePhase.MAIN)

	if resolve_effects:
		game_state.current_sub_phase = 0
		sub_phase_changed.emit(0) # Resolve Effects
		await effect_handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
		await action_handler.resolve_check_timing(game_state)

	game_state.current_sub_phase = 1
	sub_phase_changed.emit(1) # Player Actions
	_processing_action = false
	_prompt_player_actions()


func _begin_turn(player_id: int) -> void:
	if is_game_over:
		return

	game_state.current_player_id = player_id
	game_state.turn_number += 1

	log_message.emit(GameLog.turn_start(game_state.turn_number, player_id))
	turn_started.emit(player_id)

	await _execute_start_phase()


func _execute_start_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.START
	phase_started.emit(CardEnums.GamePhase.START)
	game_state.current_sub_phase = 0
	sub_phase_changed.emit(0) # Resolve Effects
	await effect_handler.trigger_phase_start(CardEnums.GamePhase.START)
	await action_handler.resolve_check_timing(game_state) # 7.2.1

	var opponent := game_state.get_opponent_of_current()

	game_state.current_sub_phase = 1
	sub_phase_changed.emit(1) # Draw Cards
	await _await_confirmation("Draw %d card(s)" % opponent.get_monster_rank(), "auto_draw")
	log_message.emit(GameLog.start_phase_draw(opponent.get_monster_rank()))
	action_handler.execute_start_phase_draw(game_state)

	game_state.current_sub_phase = 2
	sub_phase_changed.emit(2) # Discard Strategies
	await _await_confirmation("Discard Strategies", "auto_discard_strategies")
	await action_handler.execute_start_phase_discard(game_state)

	game_state.current_sub_phase = 3
	sub_phase_changed.emit(3) # Reset Rage
	await _await_confirmation("Reset Rage", "auto_reset_rage")
	await action_handler.execute_start_phase_reset(game_state)

	await action_handler.resolve_check_timing(game_state) # 7.2.5
	await effect_handler.trigger_phase_end(CardEnums.GamePhase.START)
	phase_ended.emit(CardEnums.GamePhase.START)
	await _await_confirmation("Main Phase", "auto_phase_advance")
	_begin_main_phase()


func _begin_main_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.MAIN
	phase_started.emit(CardEnums.GamePhase.MAIN)
	game_state.current_sub_phase = 0
	sub_phase_changed.emit(0) # Resolve Effects
	await effect_handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
	await action_handler.resolve_check_timing(game_state) # 7.3.1

	game_state.current_sub_phase = 1
	sub_phase_changed.emit(1) # Player Actions
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
		log_message.emit(GameLog.player_pass(game_state.current_player_id))
		await effect_handler.trigger_phase_end(CardEnums.GamePhase.MAIN)
		phase_ended.emit(CardEnums.GamePhase.MAIN)
		# Keep _processing_action = true through automated phases (COUNTER → END → START)
		# to block any submit_action calls until the next MAIN phase is ready for input.
		await _await_confirmation("Counter Phase", "auto_phase_advance")
		_begin_counter_phase()
		return

	# Action handlers emit their own log lines at the right point during execute()
	# (after the action's state mutations but before triggered effects fire), so the
	# log reads in causal order: action first, then effects fired by the action.
	await action_handler.execute(action, params, game_state)
	await action_handler.resolve_check_timing(game_state) # 10.4.4.1

	_processing_action = false

	# Check for win condition after each action
	if is_game_over:
		return

	var winner := rules_engine.check_win_condition(game_state)
	if winner >= 0:
		_on_game_over(winner, "STR_LOG_REASON_INVASION_VICTORY")
		return

	# Loop back for more actions
	_prompt_player_actions()


func _begin_counter_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.COUNTER
	phase_started.emit(CardEnums.GamePhase.COUNTER)
	game_state.current_sub_phase = 0
	sub_phase_changed.emit(0) # Resolve Effects
	await effect_handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
	await action_handler.resolve_check_timing(game_state) # 7.4.1

	game_state.current_sub_phase = 1
	sub_phase_changed.emit(1) # Counter Check
	await _await_confirmation("Counter Check", "auto_counter_check")
	await action_handler.resolve_counter(game_state)

	if is_game_over:
		return

	await action_handler.resolve_check_timing(game_state) # 7.4.4
	await effect_handler.trigger_phase_end(CardEnums.GamePhase.COUNTER)
	phase_ended.emit(CardEnums.GamePhase.COUNTER)
	await _await_confirmation("End Phase", "auto_phase_advance")
	_begin_end_phase()


func _begin_end_phase() -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.END
	phase_started.emit(CardEnums.GamePhase.END)
	game_state.current_sub_phase = 0
	sub_phase_changed.emit(0) # Resolve Effects
	await effect_handler.trigger_phase_start(CardEnums.GamePhase.END)
	await action_handler.resolve_check_timing(game_state) # 7.5.1

	var player := game_state.get_current_player()

	# Burst discard, then advance (7.5.2)
	game_state.current_sub_phase = 1
	sub_phase_changed.emit(1) # Advance
	await _await_confirmation("Advance", "auto_advance")
	await action_handler.execute_end_phase_burst_discard(game_state)
	await action_handler.execute_end_phase_advance(game_state)

	# Check win from end-phase advance
	if is_game_over:
		return

	var winner := rules_engine.check_win_condition(game_state)
	if winner >= 0:
		_on_game_over(winner, "STR_LOG_REASON_INVASION_VICTORY")
		return

	await action_handler.resolve_check_timing(game_state) # 7.5.3

	# Draw up to 5 cards (7.5.4)
	game_state.current_sub_phase = 2
	sub_phase_changed.emit(2) # Refill Hand
	var draw_count := 5 - player.hand.size()
	if draw_count > 0:
		await _await_confirmation("Draw %d card(s)" % draw_count, "auto_draw")
	action_handler.execute_end_phase_draw(game_state)

	await action_handler.resolve_check_timing(game_state) # 7.5.5

	await effect_handler.trigger_phase_end(CardEnums.GamePhase.END)
	phase_ended.emit(CardEnums.GamePhase.END)
	turn_ended.emit(game_state.current_player_id)

	# Switch turns
	await _await_confirmation("Next Turn", "auto_phase_advance")
	_begin_turn(1 - game_state.current_player_id)


func _on_hand_changed() -> void:
	if _waiting_for_input and not _processing_action:
		_prompt_player_actions()


func _on_game_over(winner_id: int, reason_key: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	log_message.emit(GameLog.game_over(winner_id, reason_key))
	game_ended.emit(winner_id, reason_key)
