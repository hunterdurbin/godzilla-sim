class_name EffectModule
extends RefCounted

## Base for the engine modules behind the EffectHandler facade
## (TriggerDispatcher, DestructionEngine, CardMover, MonsterMover, EnterZone,
## EffectQueries). EffectHandler.setup wires each module once with direct
## references to the others (`wire`), so cross-module calls go straight to
## the owning module (`dispatcher.collect_enter_entries`, `queries.…`) —
## never through a facade delegate. The facade `h` is used only for what the
## facade itself owns: its signals (log_message, card_evolved, …) and the
## player-prompt primitives with their UI state (select_zone_target,
## select_choice, reveal_cards, choice_source_refs, …).

var h: EffectHandler
## Copied from the facade once by `wire`: EffectHandler.setup is the only
## place that assigns game_state / input / the modules (a later reassignment
## on the facade would not reach the modules).
var game_state: GameState
var input: PlayerInput
var registry: EffectRegistry
var check_timing: CheckTiming
var dispatcher: TriggerDispatcher
var destruction: DestructionEngine
var mover: CardMover
var monster_mover: MonsterMover
var enter_zone: EnterZone
var queries: EffectQueries

## Wired after EffectHandler.setup (MatchFactory / TurnManager), so read
## through the facade on use.
var action_handler: Variant:
	get: return h.action_handler
var events: GameEvents:
	get: return h.events


func wire(hub: EffectHandler) -> void:
	h = hub
	game_state = hub.game_state
	input = hub.input
	registry = hub.registry
	check_timing = hub.check_timing
	dispatcher = hub.dispatcher
	destruction = hub.destruction
	mover = hub.mover
	monster_mover = hub.monster_mover
	enter_zone = hub.enter_zone
	queries = hub.queries


func unwire() -> void:
	## Break the module <-> module / facade reference cycles (teardown).
	h = null
	game_state = null
	input = null
	registry = null
	check_timing = null
	dispatcher = null
	destruction = null
	mover = null
	monster_mover = null
	enter_zone = null
	queries = null


func get_effect(card_data: Dictionary) -> CardEffect:
	return registry.get_effect(card_data)


func has_trigger(card_data: Dictionary, method_name: String) -> bool:
	return registry.has_trigger(card_data, method_name)


func get_trigger_filter(card_data: Dictionary, method_name: String) -> Dictionary:
	return registry.get_trigger_filter(card_data, method_name)


func _build_context(owner_id: int, card_data: Dictionary) -> EffectContext:
	return EffectContext.create(game_state, owner_id, card_data, h)


func _highlight_active_effect() -> void:
	h._highlight_active_effect()


func _unhighlight_active_effect() -> void:
	h._unhighlight_active_effect()


func _get_card_location_label(player_id: int, card_data: Dictionary) -> String:
	return CheckTiming.card_location_label(game_state, player_id, card_data)
