class_name EffectModule
extends RefCounted

## Base for the classes split out of the EffectHandler facade
## (TriggerDispatcher, DestructionEngine, CardMover, MonsterMover,
## EffectQueries). Each module holds the facade hub `h` and shares its
## game state, input port, check timing, and registry through the
## forwarders below — so module code reads like it did when it lived on
## the facade, and cross-module calls go through `h.<method>` delegates.

var h: EffectHandler

var game_state: GameState:
	get: return h.game_state
var input: PlayerInput:
	get: return h.input
var action_handler: Variant:
	get: return h.action_handler
var check_timing: CheckTiming:
	get: return h.check_timing


func get_effect(card_data: Dictionary) -> CardEffect:
	return h.get_effect(card_data)


func has_trigger(card_data: Dictionary, method_name: String) -> bool:
	return h.has_trigger(card_data, method_name)


func get_trigger_filter(card_data: Dictionary, method_name: String) -> Dictionary:
	return h.get_trigger_filter(card_data, method_name)


func _build_context(owner_id: int, card_data: Dictionary) -> EffectContext:
	return h._build_context(owner_id, card_data)


func _resolve_standby_entries(entries: Array) -> void:
	await h.check_timing.submit(entries)


func resolve_deferred_entries(entries: Array) -> void:
	await h.check_timing.submit_deferred(entries)


func is_card_still_active(player_id: int, card_data: Dictionary) -> bool:
	return h.is_card_still_active(player_id, card_data)


func _highlight_active_effect() -> void:
	h._highlight_active_effect()


func _unhighlight_active_effect() -> void:
	h._unhighlight_active_effect()


func _get_card_location_label(player_id: int, card_data: Dictionary) -> String:
	return h._get_card_location_label(player_id, card_data)
