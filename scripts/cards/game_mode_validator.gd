class_name GameModeValidator
## Validates decklists against game mode-specific rules and exposes the
## per-mode card pool used by the deck builder to show only legal cards.
##
## Each mode's `card_pool` dict may contain:
##   include_sets       : Array[String] — whole sets added to the pool
##   include_cards      : Array[String] — specific card IDs added beyond `include_sets`
##   exclude_cards      : Array[String] — ban list; wins over every include above
##   restricted         : Array[String] — max 1 copy across monster + main
##   choice_restricted  : Array[Array[String]] — pair lists; only one per pair allowed
## Modes without a `card_pool` (e.g. no_rules) accept every card and run no
## per-pool checks.

const _BULKZILLA_POOL = preload("res://scripts/cards/pools/bulkzilla_card_pool.gd")

const MODES: Array[Dictionary] = [
	{
		"id": "rumble_west",
		"label": "STR_MODE_RUMBLE_WEST",
		"desc": "STR_MODE_RUMBLE_WEST_DESC",
		# West format tracks the Western release. Update `include_sets`
		# below as new sets reach the Western release.
		"card_pool": {
			"include_sets": ["EBP01", "EBP02", "EBP03", "EBP04", "EFC01", "ESD01", "ESD02", "EPR", "ESC01"],
			"include_cards": [],
			"exclude_cards": ["EPR-004"],
			"restricted": ["EBP01-077"],
			"choice_restricted": [["EBP02-003", "EBP03-035"]],
		},
	},
	{
		"id": "rumble_east",
		"label": "STR_MODE_RUMBLE_EAST",
		"desc": "STR_MODE_RUMBLE_EAST_DESC",
		# East format tracks the latest Japanese release. Contains every
		# currently-implemented set.
		"card_pool": {
			"include_sets": ["EBP01", "EBP02", "EBP03", "EBP04", "EFC01", "ESD01", "ESD02", "EPR", "ESC01"],
			"include_cards": [],
			"exclude_cards": ["ESD01-016"],
			"restricted": ["EBP01-077"],
			"choice_restricted": [["EBP02-003", "EBP03-035"]],
		},
	},
	{
		"id": "no_rules",
		"label": "STR_MODE_NO_RULES",
		"desc": "STR_MODE_NO_RULES_DESC",
		# No `card_pool` → every card is valid and no per-pool checks run.
	},
	{
		"id": "bulkzilla",
		"label": "STR_MODE_BULKZILLA",
		"desc": "STR_MODE_BULKZILLA_DESC",
		# BULKZILLA: starter decks plus any common/uncommon booster cards.
		# The individual allow list lives in `scripts/cards/pools/bulkzilla_card_pool.gd`
		# (rarity-annotated for readability) and is spliced in at runtime
		# via `_get_resolved_modes`. Keep this `include_cards` slot empty.
		"card_pool": {
			"include_sets": ["ESD01", "ESD02"],
			"include_cards": [],
			"exclude_cards": [],
			"restricted": [],
			"choice_restricted": [],
		},
	},
]

const ERR_RESTRICTED := "STR_VALIDATE_RESTRICTED_FMT"
const ERR_CHOICE_RESTRICTED := "STR_VALIDATE_CHOICE_RESTRICTED_FMT"
const ERR_NOT_IN_FORMAT := "STR_VALIDATE_NOT_IN_FORMAT_FMT"


static func normalize_mode_id(game_mode: String) -> String:
	## Legacy saved decks and server rooms may use the old "rumble" id before
	## the East/West split. Map it to rumble_west (the new default).
	if game_mode == "rumble":
		return "rumble_west"
	return game_mode


static var _modes_resolved: Array[Dictionary] = []


static func _get_resolved_modes() -> Array[Dictionary]:
	## Returns MODES with any dynamic pool data injected. Currently this
	## means splicing BulkzillaCardPool.CARDS into the BULKZILLA entry's
	## `include_cards`. Cached on first access; the data files are loaded
	## at project start so cache invalidation isn't a concern.
	if _modes_resolved.is_empty():
		_modes_resolved = MODES.duplicate(true)
		for m in _modes_resolved:
			if m.get("id") == "bulkzilla":
				m.card_pool.include_cards = _BULKZILLA_POOL.CARDS.duplicate()
	return _modes_resolved


static func get_mode(game_mode: String) -> Dictionary:
	var lookup := normalize_mode_id(game_mode)
	for m in _get_resolved_modes():
		if m.id == lookup:
			return m
	return {}


static func get_mode_label(mode_id: String) -> String:
	var m := get_mode(mode_id)
	if m.is_empty():
		return mode_id
	return Loc.t(m.label)


static func is_card_valid_for_mode(card_number: String, game_mode: String) -> bool:
	## Valid-card engine. Priority order (first match wins):
	##   1. `exclude_cards` ban list — wins over everything; lets you drop a
	##      single card without removing the whole set.
	##   2. `include_cards` allow list — adds specific cards even when their
	##      set isn't in `include_sets`.
	##   3. `include_sets` allow list — the card's set prefix must appear.
	## Modes without a `card_pool` entry (e.g. no_rules) accept every card.
	## `card_number` may include a "+" reprint suffix; we match on the base.
	var m := get_mode(game_mode)
	if m.is_empty() or not m.has("card_pool"):
		return true
	var pool: Dictionary = m["card_pool"]
	var base: String = card_number.trim_suffix("+")
	if base in pool.get("exclude_cards", []):
		return false
	if base in pool.get("include_cards", []):
		return true
	var set_prefix: String = base.split("-")[0]
	return set_prefix in pool.get("include_sets", [])


static func validate(game_mode: String, monster_entries: Array, main_entries: Array) -> Array[String]:
	## Returns an array of error strings for the given mode. Empty = valid.
	var normalized := normalize_mode_id(game_mode)
	if normalized == "no_rules":
		var empty: Array[String] = []
		return empty
	var errors := DeckValidator.validate(monster_entries, main_entries, CardData.printing_for_mode(game_mode))
	var m := get_mode(game_mode)
	if not m.is_empty() and m.has("card_pool"):
		errors.append_array(_validate_pool_restrictions(m, monster_entries, main_entries))
	return errors


static func get_invalid_cards(game_mode: String, monster_entries: Array, main_entries: Array) -> Dictionary:
	## Returns card_number -> true for cards with per-card errors in the given mode.
	var normalized := normalize_mode_id(game_mode)
	if normalized == "no_rules":
		return {}
	var invalid := DeckValidator.get_invalid_cards(monster_entries, main_entries, CardData.printing_for_mode(game_mode))
	var m := get_mode(game_mode)
	if not m.is_empty() and m.has("card_pool"):
		_flag_pool_invalid(m.card_pool, game_mode, monster_entries, main_entries, invalid)
	return invalid


static func _count_by_base(entries: Array) -> Dictionary:
	var counts: Dictionary = {}
	for entry in entries:
		var base: String = entry["card_number"].trim_suffix("+")
		counts[base] = counts.get(base, 0) + entry["quantity"]
	return counts


static func _flag_pool_invalid(pool: Dictionary, game_mode: String, monster_entries: Array, main_entries: Array, invalid: Dictionary) -> void:
	var all_entries: Array = monster_entries + main_entries
	var card_counts: Dictionary = _count_by_base(all_entries)

	# Cards not in the format's allow list (out-of-format / banned).
	for entry in all_entries:
		var cn: String = entry["card_number"]
		if not is_card_valid_for_mode(cn, game_mode):
			invalid[cn] = true

	# Restricted: flag every copy if the base id is over limit.
	for cn in pool.get("restricted", []):
		if card_counts.get(cn, 0) > 1:
			for entry in all_entries:
				if entry["card_number"].trim_suffix("+") == cn:
					invalid[entry["card_number"]] = true

	# Choice restricted: flag every copy of both cards when both appear.
	for pair in pool.get("choice_restricted", []):
		if card_counts.get(pair[0], 0) > 0 and card_counts.get(pair[1], 0) > 0:
			for entry in all_entries:
				var base: String = entry["card_number"].trim_suffix("+")
				if base == pair[0] or base == pair[1]:
					invalid[entry["card_number"]] = true


static func _validate_pool_restrictions(mode: Dictionary, monster_entries: Array, main_entries: Array) -> Array[String]:
	var errors: Array[String] = []
	var pool: Dictionary = mode["card_pool"]
	var mode_id: String = mode.get("id", "")
	var format_label: String = Loc.t(mode.get("label", ""))
	var card_counts: Dictionary = _count_by_base(monster_entries + main_entries)
	var seen_out_of_format: Dictionary = {}

	# Out-of-format check: any entry the pool's allow/exclude rules reject.
	for entry in monster_entries + main_entries:
		var cn: String = entry["card_number"]
		var base: String = cn.trim_suffix("+")
		if seen_out_of_format.has(base):
			continue
		if not is_card_valid_for_mode(cn, mode_id):
			seen_out_of_format[base] = true
			var tmpl: Dictionary = CardData.CARD_TEMPLATES.get(cn, {})
			var card_name: String = tmpl.get("name", base)
			errors.append(Loc.t(ERR_NOT_IN_FORMAT) % [card_name, base, format_label])

	# Restricted list: max 1 copy across monster + main decks.
	for cn in pool.get("restricted", []):
		if card_counts.get(cn, 0) > 1:
			errors.append(Loc.t(ERR_RESTRICTED) % [cn, card_counts[cn]])

	# Choice restricted: mutually exclusive pairs.
	for pair in pool.get("choice_restricted", []):
		if card_counts.get(pair[0], 0) > 0 and card_counts.get(pair[1], 0) > 0:
			errors.append(Loc.t(ERR_CHOICE_RESTRICTED) % [pair[0], pair[1]])

	return errors
