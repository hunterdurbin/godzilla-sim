class_name EffectModule
extends RefCounted

## Base for the classes split out of the EffectHandler facade
## (TriggerDispatcher, DestructionEngine, CardMover, MonsterMover,
## EffectQueries). Each module holds the facade hub `h` and shares its
## game state, input port, execution state, and registry through the
## forwarders below — so module code reads like it did when it lived on
## the facade, and cross-module calls go through `h.<method>` delegates.

var h: EffectHandler

var game_state: GameState:
	get: return h.game_state
var input: PlayerInput:
	get: return h.input
var action_handler: Variant:
	get: return h.action_handler
@warning_ignore("unused_private_class_variable") # used by module subclasses
var _active_effect_player_id: int:
	get: return h.exec.active_player_id
	set(v): h.exec.active_player_id = v
@warning_ignore("unused_private_class_variable")
var _active_effect_card: Dictionary:
	get: return h.exec.active_card
	set(v): h.exec.active_card = v
@warning_ignore("unused_private_class_variable")
var _in_standby_resolution: bool:
	get: return h.exec.in_standby_resolution
	set(v): h.exec.in_standby_resolution = v
@warning_ignore("unused_private_class_variable")
var _pending_standby_entries: Array:
	get: return h.exec.pending_standby_entries
	set(v): h.exec.pending_standby_entries = v


func get_effect(card_data: Dictionary) -> CardEffect:
	return h.get_effect(card_data)


func has_trigger(card_data: Dictionary, method_name: String) -> bool:
	return h.has_trigger(card_data, method_name)


func get_trigger_filter(card_data: Dictionary, method_name: String) -> Dictionary:
	return h.get_trigger_filter(card_data, method_name)


func _build_context(owner_id: int, card_data: Dictionary) -> EffectContext:
	return h._build_context(owner_id, card_data)


func _resolve_standby_entries(entries: Array) -> void:
	await h._resolve_standby_entries(entries)


func resolve_deferred_entries(entries: Array) -> void:
	await h.resolve_deferred_entries(entries)


func is_card_still_active(player_id: int, card_data: Dictionary) -> bool:
	return h.is_card_still_active(player_id, card_data)


func _set_active_effect(player_id: int, card_data: Dictionary) -> void:
	h._set_active_effect(player_id, card_data)


func _clear_active_effect() -> void:
	h._clear_active_effect()


func _highlight_active_effect() -> void:
	h._highlight_active_effect()


func _unhighlight_active_effect() -> void:
	h._unhighlight_active_effect()


func _get_card_location_label(player_id: int, card_data: Dictionary) -> String:
	return h._get_card_location_label(player_id, card_data)
