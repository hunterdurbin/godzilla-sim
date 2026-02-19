class_name GameModeValidator
## Validates decklists against game mode-specific rules.

const MODES: Array[Dictionary] = [
	{"id": "rumble", "label": "Rumble"},
	{"id": "no_rules", "label": "No Rules"},
]


static func validate(game_mode: String, monster_entries: Array, main_entries: Array) -> Array[String]:
	## Returns an array of error strings for the given mode. Empty = valid.
	match game_mode:
		"rumble":
			return DeckValidator.validate(monster_entries, main_entries)
		"no_rules":
			var empty: Array[String] = []
			return empty
		_:
			return DeckValidator.validate(monster_entries, main_entries)


static func get_mode_label(mode_id: String) -> String:
	for m in MODES:
		if m.id == mode_id:
			return m.label
	return mode_id
