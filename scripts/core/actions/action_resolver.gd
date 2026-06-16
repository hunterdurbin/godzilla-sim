class_name ActionResolver
extends RefCounted

## Base for the resolvers split out of ActionHandler (PlayActions,
## InvasionResolver, CounterResolver, RuleActions, PhaseActions). Each holds
## the ActionHandler hub `ah` and reaches the shared collaborators through
## the lazy forwarders below, so wiring order doesn't matter.

var ah: ActionHandler

var effect_handler: EffectHandler:
	get: return ah.effect_handler
var input: PlayerInput:
	get: return ah.input
var events: GameEvents:
	get: return ah.events


func _traits_overlap(traits_a: Array, traits_b: Array) -> bool:
	for t in traits_a:
		if t in traits_b:
			return true
	return false
