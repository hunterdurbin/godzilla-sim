class_name TurnManager
extends RefCounted

## Core state machine driving the Godzilla TCG game loop:
## START → MAIN (player actions) → COUNTER → END → next turn.
## Construction and wiring live in MatchFactory; player decisions (including
## phase-step confirmations) go through the injected PlayerInput.

signal phase_started(phase: CardEnums.GamePhase)
signal phase_ended(phase: CardEnums.GamePhase)
signal sub_phase_changed(sub_index: int)
signal awaiting_player_action(valid_actions: Array)
signal turn_started(player_id: int)
signal turn_ended(player_id: int)
# Emitted by MatchFactory at the end of setup, not from this class.
@warning_ignore("unused_signal")
signal game_started()
signal game_ended(winner_id: int, reason_key: String)
signal log_message(token: Dictionary)

## Where the loop currently is, replacing the old _processing_action /
## _waiting_for_input flag pair with explicit states:
##  IDLE              — before start_game()
##  AWAITING_ACTION   — main phase, waiting for submit_action()
##  PROCESSING_ACTION — a submitted action is executing
##  ADVANCING_PHASES  — automated phase flow (START / COUNTER / END)
##  GAME_OVER         — terminal
enum FlowState { IDLE, AWAITING_ACTION, PROCESSING_ACTION, ADVANCING_PHASES, GAME_OVER }

var game_state: GameState
var rules_engine: RulesEngine
var action_handler: ActionHandler
var effect_handler: EffectHandler
## Gameplay notification bus (presentation / sync / sfx subscribe here).
var events: GameEvents
## The session's player-decision port. Assign before setup() to inject a
## custom implementation (tests use ScriptedPlayerInput); defaults to
## SignalPlayerInput for live play.
var player_input: PlayerInput
var session_config: SessionConfig
var is_game_over: bool = false
var flow_state: FlowState = FlowState.IDLE


# --- Construction (delegates to MatchFactory) ---

func setup(card_data_node: Node, config: SessionConfig = null) -> void:
	MatchFactory.setup(self, card_data_node, config)


func setup_from_save(data: Dictionary) -> void:
	## Restore a game from a saved state dictionary.
	MatchFactory.setup_from_save(self, data)


func teardown() -> void:
	## Break the match's internal RefCounted reference cycles so the whole
	## component graph can be freed once the owner drops its reference —
	## without this, EffectHandler <-> modules / ActionHandler <-> resolvers
	## keep every match object alive forever ("ObjectDB instances leaked at
	## exit"). Idempotent; safe with suspended effect coroutines (flags are
	## set first so anything that still resumes bails on the existing
	## is_game_over guards, and the PlayerInput drops pending decisions so
	## late resolve_*() calls become no-ops).
	is_game_over = true
	flow_state = FlowState.GAME_OVER
	if player_input:
		player_input.teardown()
	if effect_handler:
		effect_handler.teardown()
	if action_handler:
		action_handler.teardown()
	effect_handler = null
	action_handler = null
	rules_engine = null
	events = null
	player_input = null
	# game_state intentionally kept: session forwarders may still read it
	# during the frame the owning scene exits.


# --- Game flow ---

func start_game(first_player_id: int = 0) -> void:
	_begin_turn(first_player_id)


func resume_game() -> void:
	## Resume a loaded game at the restored (phase, sub_phase) boundary.
	## Boundary snapshots are captured at sub-phase ENTRY, before the step
	## runs — resume executes the saved sub-phase's step and everything after,
	## then flows naturally into later phases/turns.
	## Saves taken mid-sub-phase re-run that sub-phase from its entry, so
	## partially resolved effects may re-apply; turn-scoped effect-handler
	## state (e.g. "until end of turn" modifiers) is not serialized.
	var from_sub: int = game_state.current_sub_phase
	flow_state = FlowState.ADVANCING_PHASES

	log_message.emit(GameLog.turn_start(game_state.turn_number, game_state.current_player_id))
	turn_started.emit(game_state.current_player_id)

	match game_state.current_phase:
		CardEnums.GamePhase.START:
			await _execute_start_phase(from_sub)
		CardEnums.GamePhase.MAIN:
			await _begin_main_phase(from_sub)
		CardEnums.GamePhase.COUNTER:
			await _begin_counter_phase(from_sub)
		CardEnums.GamePhase.END:
			await _begin_end_phase(from_sub)
		_:
			await _execute_start_phase()


func submit_action(action: CardEnums.ActionType, params: Dictionary = {}) -> void:
	if is_game_over or flow_state != FlowState.AWAITING_ACTION:
		return
	flow_state = FlowState.PROCESSING_ACTION

	if action == CardEnums.ActionType.PASS:
		log_message.emit(GameLog.player_pass(game_state.current_player_id))
		await effect_handler.trigger_phase_end(CardEnums.GamePhase.MAIN)
		phase_ended.emit(CardEnums.GamePhase.MAIN)
		# Stay out of AWAITING_ACTION through the automated phases
		# (COUNTER → END → START) so submit_action calls are dropped until
		# the next MAIN phase is ready for input.
		flow_state = FlowState.ADVANCING_PHASES
		await _await_confirmation("Counter Phase", "auto_phase_advance")
		_begin_counter_phase()
		return

	# Action handlers emit their own log lines at the right point during execute()
	# (after the action's state mutations but before triggered effects fire), so the
	# log reads in causal order: action first, then effects fired by the action.
	await action_handler.execute(action, params, game_state)
	await action_handler.resolve_check_timing(game_state) # 10.4.4.1

	# Check for win condition after each action
	if is_game_over:
		return

	var winner := rules_engine.check_win_condition(game_state)
	if winner >= 0:
		_on_game_over(winner, "STR_LOG_REASON_INVASION_VICTORY")
		return

	# Loop back for more actions
	_prompt_player_actions()


# --- Internal phase machine ---

func _await_confirmation(prompt: String, setting: String) -> void:
	# Not redundant: SignalPlayerInput's confirm_step override is a coroutine.
	@warning_ignore("redundant_await")
	await player_input.confirm_step(game_state.current_player_id, prompt, setting)


func _begin_turn(player_id: int) -> void:
	if is_game_over:
		return

	flow_state = FlowState.ADVANCING_PHASES
	game_state.current_player_id = player_id
	game_state.turn_number += 1

	log_message.emit(GameLog.turn_start(game_state.turn_number, player_id))
	turn_started.emit(player_id)

	await _execute_start_phase()


func _execute_start_phase(from_sub: int = 0) -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.START
	phase_started.emit(CardEnums.GamePhase.START)

	if from_sub <= 0:
		game_state.current_sub_phase = 0
		sub_phase_changed.emit(0) # Resolve Effects
		await effect_handler.trigger_phase_start(CardEnums.GamePhase.START)
		await action_handler.resolve_check_timing(game_state) # 7.2.1

	var opponent := game_state.get_opponent_of_current()

	if from_sub <= 1:
		game_state.current_sub_phase = 1
		sub_phase_changed.emit(1) # Draw Cards
		await _await_confirmation("Draw %d card(s)" % opponent.get_monster_rank(), "auto_draw")
		log_message.emit(GameLog.start_phase_draw(opponent.get_monster_rank()))
		action_handler.execute_start_phase_draw(game_state)

	if from_sub <= 2:
		game_state.current_sub_phase = 2
		sub_phase_changed.emit(2) # Discard Strategies
		await _await_confirmation("Discard Strategies", "auto_discard_strategies")
		await action_handler.execute_start_phase_discard(game_state)

	if from_sub <= 3:
		game_state.current_sub_phase = 3
		sub_phase_changed.emit(3) # Reset Rage
		await _await_confirmation("Reset Rage", "auto_reset_rage")
		await action_handler.execute_start_phase_reset(game_state)

	await action_handler.resolve_check_timing(game_state) # 7.2.5
	await effect_handler.trigger_phase_end(CardEnums.GamePhase.START)
	phase_ended.emit(CardEnums.GamePhase.START)
	await _await_confirmation("Main Phase", "auto_phase_advance")
	_begin_main_phase()


func _begin_main_phase(from_sub: int = 0) -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.MAIN
	phase_started.emit(CardEnums.GamePhase.MAIN)

	if from_sub <= 0:
		game_state.current_sub_phase = 0
		sub_phase_changed.emit(0) # Resolve Effects
		await effect_handler.trigger_phase_start(CardEnums.GamePhase.MAIN)
		await action_handler.resolve_check_timing(game_state) # 7.3.1

	game_state.current_sub_phase = 1
	sub_phase_changed.emit(1) # Player Actions
	_prompt_player_actions()


func _prompt_player_actions() -> void:
	if is_game_over:
		return

	flow_state = FlowState.AWAITING_ACTION
	var valid_actions := rules_engine.get_valid_actions(game_state)
	awaiting_player_action.emit(valid_actions)


func _begin_counter_phase(from_sub: int = 0) -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.COUNTER
	phase_started.emit(CardEnums.GamePhase.COUNTER)

	if from_sub <= 0:
		game_state.current_sub_phase = 0
		sub_phase_changed.emit(0) # Resolve Effects
		await effect_handler.trigger_phase_start(CardEnums.GamePhase.COUNTER)
		await action_handler.resolve_check_timing(game_state) # 7.4.1

	if from_sub <= 1:
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


func _begin_end_phase(from_sub: int = 0) -> void:
	if is_game_over:
		return

	game_state.current_phase = CardEnums.GamePhase.END
	phase_started.emit(CardEnums.GamePhase.END)

	if from_sub <= 0:
		game_state.current_sub_phase = 0
		sub_phase_changed.emit(0) # Resolve Effects
		await effect_handler.trigger_phase_start(CardEnums.GamePhase.END)
		await action_handler.resolve_check_timing(game_state) # 7.5.1

	var player := game_state.get_current_player()

	if from_sub <= 1:
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

	if from_sub <= 2:
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
	# Recompute valid actions if the hand changed while waiting for input
	# (e.g. an effect added cards mid-main-phase).
	if flow_state == FlowState.AWAITING_ACTION:
		_prompt_player_actions()


func _on_game_over(winner_id: int, reason_key: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	flow_state = FlowState.GAME_OVER
	log_message.emit(GameLog.game_over(winner_id, reason_key))
	game_ended.emit(winner_id, reason_key)
