extends RefCounted

## Builders for REAL card dictionaries (with effect_script wired) from the
## CardData autoload, for per-card effect tests.
##
## CardData.get_card_by_id returns the live template reference and trigger
## dispatch mutates card dicts (e.g. played_from_effect), so tests must never
## touch a raw template — instance() deep-copies and stamps a per-copy
## instance id, matching the "<base>_<deck>_<n>" convention deck builders use.


## A playable copy of the card with the given base id. `copy` distinguishes
## multiple copies of the same card within one test (distinct instance ids).
static func instance(id: String, copy: int = 0) -> Dictionary:
	var template: Dictionary = CardData.get_card_by_id(id)
	assert(not template.is_empty(), "RealCards: unknown card id %s" % id)
	var card: Dictionary = template.duplicate(true)
	card["id"] = "%s_T_%d" % [id, copy]
	return card


## All base ids in CARD_TEMPLATES that carry an effect script, sorted.
static func ids_with_effects() -> Array[String]:
	var ids: Array[String] = []
	for id in CardData.CARD_TEMPLATES:
		var script_path: String = CardData.CARD_TEMPLATES[id].get("effect_script", "")
		if not script_path.is_empty():
			ids.append(id)
	ids.sort()
	return ids


## Base ids with effects whose script lives under scripts/effects/<set_prefix>/
## (e.g. "ebp01"), sorted.
static func ids_for_set(set_prefix: String) -> Array[String]:
	var ids: Array[String] = []
	for id in ids_with_effects():
		var script_path: String = CardData.CARD_TEMPLATES[id].get("effect_script", "")
		if script_path.begins_with("res://scripts/effects/%s/" % set_prefix):
			ids.append(id)
	return ids
