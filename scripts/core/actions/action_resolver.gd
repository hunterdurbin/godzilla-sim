class_name ActionResolver
extends RefCounted

## Base for the resolvers split out of ActionHandler (PlayActions,
## InvasionResolver, CounterResolver, PhaseActions). Each holds
## the ActionHandler hub `ah` and reaches the shared collaborators through
## the lazy forwarders below, so wiring order doesn't matter. The engine
## modules (dispatcher, queries, check_timing, ...) are called directly —
## the EffectHandler facade is the card-script interface; resolvers use it
## only for what it owns (log_message, the select_choice prompt).

var ah: ActionHandler

var effect_handler: EffectHandler:
	get: return ah.effect_handler
var input: PlayerInput:
	get: return ah.input
var events: GameEvents:
	get: return ah.events
var registry: EffectRegistry:
	get: return ah.effect_handler.registry
var check_timing: CheckTiming:
	get: return ah.effect_handler.check_timing
var dispatcher: TriggerDispatcher:
	get: return ah.effect_handler.dispatcher
var destruction: DestructionEngine:
	get: return ah.effect_handler.destruction
var mover: CardMover:
	get: return ah.effect_handler.mover
var monster_mover: MonsterMover:
	get: return ah.effect_handler.monster_mover
var enter_zone: EnterZone:
	get: return ah.effect_handler.enter_zone
var queries: EffectQueries:
	get: return ah.effect_handler.queries


func _traits_overlap(traits_a: Array, traits_b: Array) -> bool:
	for t in traits_a:
		if t in traits_b:
			return true
	return false
