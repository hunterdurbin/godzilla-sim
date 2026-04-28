extends Node
## Autoload singleton: manages deck list files and selected deck state.

const DECKLIST_DIR := "user://decklists/"
const DECK_EXTENSION := ".deck"

## Per-player deck selections. Index 0 = player 0, index 1 = player 1.
## Each entry is either null or {"deck_name": String, "monster_deck": Array, "main_entries": Array}
var _player_decks: Array = [null, null]

const LINE_DELIMITER_MONSTER_DECK := '[monster deck]'
const LINE_DELIMITER_MAIN_DECK := '[main deck]'

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DECKLIST_DIR)
	if get_all_decklists().is_empty():
		_create_default_decklist()


# --- Public API ---

func get_all_decklists() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(DECKLIST_DIR)
	if not dir:
		return names
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(DECK_EXTENSION):
			names.append(file.trim_suffix(DECK_EXTENSION))
		file = dir.get_next()
	names.sort()
	return names


func load_decklist(deck_name: String) -> Dictionary:
	var path := DECKLIST_DIR + sanitize_filename(deck_name) + DECK_EXTENSION
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var content := file.get_as_text()
	file.close()
	return _parse_decklist(content)


func select_deck_for_player(player_id: int, deck_name: String) -> bool:
	var data := load_decklist(deck_name)
	if data.is_empty():
		return false
	_player_decks[player_id] = {
		"deck_name": deck_name,
		"monster_deck": _build_monster_deck(data["monster"]),
		"main_entries": data["main"],
	}
	return true


func set_player_deck_from_entries(player_id: int, deck_name: String, monster_entries: Array, main_entries: Array) -> void:
	_player_decks[player_id] = {
		"deck_name": deck_name,
		"monster_deck": _build_monster_deck(monster_entries),
		"main_entries": main_entries,
	}


func has_player_deck(player_id: int) -> bool:
	return _player_decks[player_id] != null


func get_player_deck_name(player_id: int) -> String:
	if _player_decks[player_id] == null:
		return ""
	return _player_decks[player_id]["deck_name"]


func get_player_monster_deck(player_id: int) -> Array[Dictionary]:
	if _player_decks[player_id] == null:
		return []
	return _player_decks[player_id]["monster_deck"]


func build_main_deck_for_player(deck_id: int) -> Array[Dictionary]:
	var entries: Array = []
	if _player_decks[deck_id] != null:
		entries = _player_decks[deck_id]["main_entries"]
	var deck: Array[Dictionary] = []
	for entry in entries:
		var template: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		if template.is_empty():
			push_warning("DecklistManager: card not found in registry: %s" % entry["card_number"])
			continue
		for i in range(entry["quantity"]):
			var card := template.duplicate()
			card["id"] = "%s_%d_%d" % [entry["card_number"], deck_id, i]
			deck.append(card)
	return deck


func clear_selections() -> void:
	_player_decks = [null, null]


func validate_decklist(deck_name: String) -> Array[String]:
	## Returns an array of error strings. Empty array = valid deck.
	var data := load_decklist(deck_name)
	if data.is_empty():
		return ["Could not load decklist."]
	return DeckValidator.validate(data["monster"], data["main"])


func get_decklist_warnings(deck_name: String) -> Array[String]:
	## Returns an array of warning strings (e.g. no valid rank-up path).
	var data := load_decklist(deck_name)
	if data.is_empty():
		return []
	return DeckValidator.warnings(data["monster"], data["main"])


func get_decklist_preview(deck_name: String) -> String:
	var data := load_decklist(deck_name)
	if data.is_empty():
		return "Could not load decklist."

	var text := ""
	text += "[b]Monster Deck[/b]\n"
	for entry in data["monster"]:
		var template: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		var card_name: String = template.get("name", entry["card_number"])
		text += "  %dx %s [%s]\n" % [entry["quantity"], card_name, entry["card_number"]]

	text += "\n[b]Main Deck[/b]\n"
	var total := 0
	for entry in data["main"]:
		var template: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		var card_name: String = template.get("name", entry["card_number"])
		var card_type_str := ""
		match template.get("card_type", -1):
			CardEnums.CardType.MONSTER:
				card_type_str = "Monster"
			CardEnums.CardType.BATTLE:
				card_type_str = "Battle"
			CardEnums.CardType.STRATEGY:
				card_type_str = "Strategy"
		text += "  %dx %s [%s] %s\n" % [entry["quantity"], card_name, entry["card_number"], card_type_str]
		total += entry["quantity"]
	text += "\nTotal: %d cards" % total

	# Append validation errors if any
	var errors := validate_decklist(deck_name)
	if not errors.is_empty():
		text += "\n\n[color=red][b]Invalid Deck[/b][/color]\n"
		for err in errors:
			text += "[color=red]- %s[/color]\n" % err

	# Append warnings if any
	var warnings := get_decklist_warnings(deck_name)
	if not warnings.is_empty():
		text += "\n\n[color=yellow][b]Warnings[/b][/color]\n"
		for warn in warnings:
			text += "[color=yellow]- %s[/color]\n" % warn

	return text


func save_decklist(deck_name: String, monster_entries: Array, main_entries: Array) -> bool:
	var path := DECKLIST_DIR + sanitize_filename(deck_name) + DECK_EXTENSION
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false

	file.store_line(LINE_DELIMITER_MONSTER_DECK)
	for entry in monster_entries:
		file.store_line("%d %s" % [entry["quantity"], entry["card_number"]])
	file.store_line("")
	file.store_line(LINE_DELIMITER_MAIN_DECK)
	for entry in main_entries:
		file.store_line("%d %s" % [entry["quantity"], entry["card_number"]])

	file.close()
	return true


func delete_decklist(deck_name: String) -> bool:
	var path := DECKLIST_DIR + sanitize_filename(deck_name) + DECK_EXTENSION
	if not FileAccess.file_exists(path):
		return false
	DirAccess.remove_absolute(path)
	for i in range(2):
		if _player_decks[i] != null and _player_decks[i]["deck_name"] == deck_name:
			_player_decks[i] = null
	# Drop any bot-deck weight entry so the random-pool list stays in sync
	if GameSettings.bot_deck_weights.has(deck_name):
		GameSettings.bot_deck_weights.erase(deck_name)
		GameSettings.save()
	return true


static func sanitize_filename(file_name: String) -> String:
	## Remove characters illegal in Windows filenames: \ / : * ? " < > |
	return file_name.replace("\\", "_").replace("/", "_").replace(":", "-") \
		.replace("*", "_").replace("?", "_").replace("\"", "'") \
		.replace("<", "_").replace(">", "_").replace("|", "_")


# --- Internal ---

func _parse_decklist(content: String) -> Dictionary:
	var result := {"monster": [], "main": []}
	var current_section := ""

	for line in content.split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var line_lower := line.to_lower()
		if line_lower == LINE_DELIMITER_MONSTER_DECK or line_lower == "monster deck:":
			current_section = "monster"
			continue
		if line_lower == LINE_DELIMITER_MAIN_DECK or line_lower == "main deck:":
			current_section = "main"
			continue
		if current_section.is_empty():
			continue

		var parts := line.split(" ", false)
		if parts.size() >= 2:
			var qty := int(parts[0])
			var card_number := parts[1].strip_edges().to_upper()
			if qty > 0 and not card_number.is_empty():
				result[current_section].append({"quantity": qty, "card_number": card_number})

	return result


func _build_monster_deck(entries: Array) -> Array[Dictionary]:
	var deck: Array[Dictionary] = []
	for entry in entries:
		var template: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		if template.is_empty():
			push_warning("DecklistManager: monster card not found: %s" % entry["card_number"])
			continue
		for i in range(entry["quantity"]):
			var card := template.duplicate()
			card["id"] = entry["card_number"]
			deck.append(card)
	# Sort by rank so monster progression works correctly
	deck.sort_custom(func(a, b): return a.get("rank", 0) < b.get("rank", 0))
	return deck


func _create_default_decklist() -> void:
	var godzilla_minus_one := LINE_DELIMITER_MONSTER_DECK + """
1 ESD01-001
1 ESD01-002
1 ESD01-003
1 ESD01-004

""" + LINE_DELIMITER_MAIN_DECK + """
2 ESD01-002
4 ESD01-005
2 ESD01-003
4 ESD01-006
2 ESD01-004
4 ESD01-007
4 ESD01-008
4 ESD01-009
4 ESD01-011
4 ESD01-010
4 ESD01-012
2 ESD01-016
4 ESD01-013
2 ESD01-014
4 ESD01-015"""

	var heisei_godzilla := LINE_DELIMITER_MONSTER_DECK + """
1 ESD02-001
1 ESD02-002
1 ESD02-003
1 ESD02-004

""" + LINE_DELIMITER_MAIN_DECK + """
3 ESD02-003
4 ESD02-005
3 ESD02-004
4 ESD02-006
4 ESD02-007
4 ESD02-008
4 ESD02-009
4 ESD02-010
4 ESD02-011
4 ESD02-012
2 ESD02-013
2 ESD01-016
4 ESD02-014
4 ESD02-015"""

	var defaults := {
		"Starter Deck - Godzilla Minus One": godzilla_minus_one,
		"Starter Deck - Heisei Series Godzilla": heisei_godzilla,
	}
	for deck_name: String in defaults:
		var path: String = DECKLIST_DIR + sanitize_filename(deck_name) + DECK_EXTENSION
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(defaults[deck_name])
			file.close()
