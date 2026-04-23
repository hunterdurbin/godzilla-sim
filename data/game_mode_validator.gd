class_name GameModeValidator
## Validates decklists against game mode-specific rules.

const MODES: Array[Dictionary] = [
	{"id": "rumble", "label": "STR_MODE_RUMBLE"},
	{"id": "no_rules", "label": "STR_MODE_NO_RULES"},
]

# Rumble restricted list: max 1 copy across monster + main decks.
const RUMBLE_RESTRICTED: Array[String] = [
	"EBP01-077",
]

# Rumble choice restricted list: if any copy of card A appears, card B cannot (and vice-versa).
# Each entry is [card_a, card_b].
const RUMBLE_CHOICE_RESTRICTED: Array[Array] = [
	["EBP02-003", "EBP03-035"],
]

const ERR_RESTRICTED := "%s is restricted in Rumble (max 1 copy, has %d)"
const ERR_CHOICE_RESTRICTED := "%s and %s are choice restricted in Rumble (only one allowed)"


static func validate(game_mode: String, monster_entries: Array, main_entries: Array) -> Array[String]:
	## Returns an array of error strings for the given mode. Empty = valid.
	match game_mode:
		"rumble":
			var errors := DeckValidator.validate(monster_entries, main_entries)
			errors.append_array(_validate_rumble(monster_entries, main_entries))
			return errors
		"no_rules":
			var empty: Array[String] = []
			return empty
		_:
			return DeckValidator.validate(monster_entries, main_entries)


static func get_mode_label(mode_id: String) -> String:
	for m in MODES:
		if m.id == mode_id:
			return TranslationServer.translate(m.label)
	return mode_id


static func get_invalid_cards(game_mode: String, monster_entries: Array, main_entries: Array) -> Dictionary:
	## Returns card_number -> true for cards with per-card errors in the given mode.
	match game_mode:
		"no_rules":
			return {}
		"rumble":
			var invalid := DeckValidator.get_invalid_cards(monster_entries, main_entries)
			_flag_rumble_invalid(monster_entries, main_entries, invalid)
			return invalid
		_:
			return DeckValidator.get_invalid_cards(monster_entries, main_entries)


static func _flag_rumble_invalid(monster_entries: Array, main_entries: Array, invalid: Dictionary) -> void:
	var all_entries: Array = monster_entries + main_entries
	var card_counts: Dictionary = {}
	for entry in all_entries:
		var base: String = entry["card_number"].trim_suffix("+")
		card_counts[base] = card_counts.get(base, 0) + entry["quantity"]

	# Restricted: flag all copies if over limit
	for cn in RUMBLE_RESTRICTED:
		if card_counts.get(cn, 0) > 1:
			for entry in all_entries:
				if entry["card_number"].trim_suffix("+") == cn:
					invalid[entry["card_number"]] = true

	# Choice restricted: flag both cards in the pair
	for pair in RUMBLE_CHOICE_RESTRICTED:
		if card_counts.get(pair[0], 0) > 0 and card_counts.get(pair[1], 0) > 0:
			for entry in all_entries:
				var base: String = entry["card_number"].trim_suffix("+")
				if base == pair[0] or base == pair[1]:
					invalid[entry["card_number"]] = true


static func _validate_rumble(monster_entries: Array, main_entries: Array) -> Array[String]:
	var errors: Array[String] = []
	var card_counts: Dictionary = {} # base card_number -> total qty

	for entry in monster_entries:
		var base: String = entry["card_number"].trim_suffix("+")
		card_counts[base] = card_counts.get(base, 0) + entry["quantity"]
	for entry in main_entries:
		var base: String = entry["card_number"].trim_suffix("+")
		card_counts[base] = card_counts.get(base, 0) + entry["quantity"]

	# Restricted list: max 1 copy
	for cn in RUMBLE_RESTRICTED:
		if card_counts.get(cn, 0) > 1:
			errors.append(ERR_RESTRICTED % [cn, card_counts[cn]])

	# Choice restricted list: mutually exclusive cards
	for pair in RUMBLE_CHOICE_RESTRICTED:
		if card_counts.get(pair[0], 0) > 0 and card_counts.get(pair[1], 0) > 0:
			errors.append(ERR_CHOICE_RESTRICTED % [pair[0], pair[1]])

	return errors
