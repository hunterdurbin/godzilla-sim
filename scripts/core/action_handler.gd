class_name ActionHandler
extends RefCounted

## Dispatches game actions to the resolver classes that mutate GameState
## (PlayActions, InvasionResolver, CounterResolver, RuleActions,
## PhaseActions). Assumes validation has already passed.
## Gameplay notifications are emitted on the shared GameEvents bus.

var effect_handler: EffectHandler
var input: PlayerInput
var events: GameEvents

var plays := PlayActions.new()
var invasion := InvasionResolver.new()
var counter := CounterResolver.new()
var rule_actions := RuleActions.new()
var phases := PhaseActions.new()


func _init() -> void:
	plays.ah = self
	invasion.ah = self
	counter.ah = self
	rule_actions.ah = self
	phases.ah = self


func execute(action: CardEnums.ActionType, params: Dictionary, state: GameState) -> void:
	match action:
		CardEnums.ActionType.PLAY_BATTLE:
			await plays.play_battle_card(params["hand_index"], params["zone_index"], state)
		CardEnums.ActionType.PLAY_STRATEGY:
			await plays.play_strategy_card(params["hand_index"], state)
		CardEnums.ActionType.GAIN_RAGE:
			await plays.gain_rage(params["hand_index"], state)
		CardEnums.ActionType.PLAY_MONSTER:
			await plays.play_monster(params["hand_index"], state)
		CardEnums.ActionType.INVADE:
			await invasion.invade(params["hand_index"], state)


# --- Phase steps ---

func execute_start_phase_draw(state: GameState) -> void:
	phases.execute_start_phase_draw(state)


func execute_start_phase_discard(state: GameState) -> void:
	await phases.execute_start_phase_discard(state)


func execute_start_phase_reset(state: GameState) -> void:
	await phases.execute_start_phase_reset(state)


func execute_end_phase_burst_discard(state: GameState) -> void:
	await phases.execute_end_phase_burst_discard(state)


func execute_end_phase_advance(state: GameState) -> void:
	await phases.execute_end_phase_advance(state)


func execute_end_phase_draw(state: GameState) -> void:
	phases.execute_end_phase_draw(state)


# --- Counter phase ---

func resolve_counter(state: GameState) -> void:
	await counter.resolve_counter(state)


func force_counter(state: GameState, target_player_id: int) -> void:
	await counter.force_counter(state, target_player_id)


# --- Effect-driven plays ---

func play_monster_from_effect(state: GameState, player_id: int, monster_card: Dictionary) -> void:
	await plays.play_monster_from_effect(state, player_id, monster_card)


# --- Rule actions (check timing) ---

func resolve_check_timing(state: GameState) -> void:
	await rule_actions.resolve_check_timing(state)


func check_crush_rule(state: GameState, deferred_entries: Variant = null) -> void:
	await rule_actions.check_crush_rule(state, deferred_entries)


# --- Pure zone math ---

static func get_retreat_zone(current_zone: int) -> int:
	## Retreat: move back by 1 zone (5.13.2). Zone 1 stays in zone 1 (5.13.2.1).
	return maxi(current_zone - 1, 1)


static func get_counter_retreat_zone(current_zone: int) -> int:
	## Get the zone a monster moves to when countered (5.15.1.1).
	## Only zones 6, 7, 8 move — to the zone behind (4.4.5.1).
	## Zones 1-5 do not move when countered.
	match current_zone:
		6: return 5
		7: return 4
		8: return 3
	return current_zone
