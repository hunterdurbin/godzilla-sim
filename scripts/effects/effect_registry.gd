class_name EffectRegistry
extends RefCounted

## Loads and caches CardEffect instances and their declarative metadata.
## Pure lookup layer: no game-state dependency, no signals — trivially
## unit-testable, and tests can inject synthetic effects via register_for_test.

const _TriggerMap = preload("res://scripts/effects/trigger_map.gd")

var _effect_cache: Dictionary = {}  # script_path -> CardEffect instance
var _filters_cache: Dictionary = {}  # script_path -> TRIGGER_FILTERS dict (declarative trigger gating)
var _test_triggers: Dictionary = {}  # script_path -> Array[String] (test-registered override list)


func get_effect(card_data: Dictionary) -> CardEffect:
	## Load and cache a CardEffect for the given card. Returns null if no effect script.
	var script_path: String = card_data.get("effect_script", "")
	if script_path.is_empty():
		return null

	if _effect_cache.has(script_path):
		return _effect_cache[script_path]

	if not ResourceLoader.exists(script_path):
		push_warning("EffectRegistry: Effect script not found: %s" % script_path)
		return null

	var script: GDScript = load(script_path)
	if script == null:
		push_warning("EffectRegistry: Failed to load effect script: %s" % script_path)
		return null

	var effect: CardEffect = script.new()
	_effect_cache[script_path] = effect
	return effect


func has_trigger(card_data: Dictionary, method_name: String) -> bool:
	## Check if a card's effect script actually overrides the given trigger method.
	## Uses a pre-generated trigger map (source_code is stripped in export builds,
	## so runtime introspection cannot detect overrides reliably).
	## Regenerate the map: bash scripts/effects/generate_trigger_map.sh
	var script_path: String = card_data.get("effect_script", "")
	if script_path.is_empty():
		return false
	if _test_triggers.has(script_path):
		return method_name in _test_triggers[script_path]
	var triggers: Array = _TriggerMap.TRIGGERS.get(script_path, [])
	return method_name in triggers


func get_trigger_filter(card_data: Dictionary, method_name: String) -> Dictionary:
	## Read the per-method filter dict an effect script declares as a class-level
	## TRIGGER_FILTERS constant. Returns {} if the script has no filter for the method.
	## See card_effect.gd header for the supported filter keys and semantics.
	var script_path: String = card_data.get("effect_script", "")
	if script_path.is_empty():
		return {}
	if not _filters_cache.has(script_path):
		var script: Script = load(script_path)
		var consts: Dictionary = script.get_script_constant_map() if script else {}
		_filters_cache[script_path] = consts.get("TRIGGER_FILTERS", {})
	var all_filters: Dictionary = _filters_cache[script_path]
	return all_filters.get(method_name, {})


func register_for_test(script_path: String, effect: CardEffect, triggers: Array = [], filters: Dictionary = {}) -> void:
	## Test hook: register a synthetic CardEffect under a fake script path so
	## tests can exercise trigger dispatch without effect-script files on disk.
	## `triggers` lists the method names has_trigger() should report for it;
	## `filters` plays the role of the script's TRIGGER_FILTERS constant.
	_effect_cache[script_path] = effect
	_test_triggers[script_path] = triggers
	_filters_cache[script_path] = filters
