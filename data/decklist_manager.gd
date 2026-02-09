extends Node
## Autoload singleton: manages deck list files and selected deck state.

const DECKLIST_DIR := "user://decklists/"
const DECK_EXTENSION := ".deck"

## Per-player deck selections. Index 0 = player 0, index 1 = player 1.
## Each entry is either null or {"deck_name": String, "monster_deck": Array, "main_entries": Array}
var _player_decks: Array = [null, null]

const LINE_DELIMITER_MONSTER_DECK := '[Monster Deck]'
const LINE_DELIMITER_MAIN_DECK := '[Main Deck]'

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
	var path := DECKLIST_DIR + deck_name + DECK_EXTENSION
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

	var errors: Array[String] = []
	var card_number_counts: Dictionary = {}  # card_number (stripped of +) -> total count

	# --- Monster Deck ---
	var monster_total := 0
	var monster_ranks_found: Dictionary = {}  # rank -> true
	var allowed_colors: Array[int] = [CardEnums.CardColor.WHITE]  # White always allowed

	for entry in data["monster"]:
		var cn: String = entry["card_number"]
		var base_cn: String = cn.trim_suffix("+")
		var qty: int = entry["quantity"]
		monster_total += qty
		card_number_counts[base_cn] = card_number_counts.get(base_cn, 0) + qty

		var template: Dictionary = CardData.CARD_TEMPLATES.get(cn, {})
		if template.is_empty():
			errors.append("Unknown card: %s" % cn)
			continue

		if template.get("card_type") != CardEnums.CardType.MONSTER:
			errors.append("%s is not a monster card" % cn)
			continue

		if CardEnums.CardTrait.TOKEN in template.get("traits", []):
			errors.append("%s has Token trait (not allowed in decks)" % cn)

		var rank: int = template.get("rank", 0)
		for _i in range(qty):
			if rank in monster_ranks_found:
				errors.append("Duplicate monster rank %d" % rank)
			else:
				monster_ranks_found[rank] = true

		if rank == 1:
			for c: int in template.get("colors", []):
				if c not in allowed_colors:
					allowed_colors.append(c)

	if monster_total != 4:
		errors.append("Monster deck must have exactly 4 cards (has %d)" % monster_total)

	for r in [1, 2, 3, 4]:
		if r not in monster_ranks_found:
			errors.append("Monster deck missing rank %d" % r)

	# Color check for monster deck cards (second pass, now that allowed_colors is known)
	if allowed_colors.size() > 1:  # More than just WHITE
		for entry in data["monster"]:
			var template: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
			if template.is_empty():
				continue
			var card_colors: Array = template.get("colors", [])
			var has_allowed := false
			for c in card_colors:
				if c in allowed_colors:
					has_allowed = true
					break
			if not has_allowed:
				errors.append("%s [%s] color doesn't match monster deck" % [
					template.get("name", entry["card_number"]), entry["card_number"]])

	# --- Main Deck ---
	var main_total := 0
	var invasion2_count := 0

	for entry in data["main"]:
		var cn: String = entry["card_number"]
		var base_cn: String = cn.trim_suffix("+")
		var qty: int = entry["quantity"]
		main_total += qty
		card_number_counts[base_cn] = card_number_counts.get(base_cn, 0) + qty

		var template: Dictionary = CardData.CARD_TEMPLATES.get(cn, {})
		if template.is_empty():
			errors.append("Unknown card: %s" % cn)
			continue

		if CardEnums.CardTrait.TOKEN in template.get("traits", []):
			errors.append("%s has Token trait (not allowed in decks)" % cn)

		if template.get("invasion_icon", 0) >= 2:
			invasion2_count += qty

		# Color check: card must have at least one allowed color
		if allowed_colors.size() > 1:  # More than just WHITE
			var card_colors: Array = template.get("colors", [])
			var has_allowed := false
			for c in card_colors:
				if c in allowed_colors:
					has_allowed = true
					break
			if not has_allowed:
				var card_name: String = template.get("name", cn)
				errors.append("%s [%s] color doesn't match monster deck" % [card_name, cn])

	if main_total != 50:
		errors.append("Main deck must have exactly 50 cards (has %d)" % main_total)

	if invasion2_count > 10:
		errors.append("Main deck has %d Step-2 cards (max 10)" % invasion2_count)

	# --- Cross-deck copy limit ---
	for cn in card_number_counts:
		if card_number_counts[cn] > 4:
			var tmpl: Dictionary = CardData.CARD_TEMPLATES.get(cn, {})
			if not tmpl.get("unlimited_copies", false):
				errors.append("Card %s has %d copies (max 4)" % [cn, card_number_counts[cn]])

	return errors


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

	return text


func save_decklist(deck_name: String, monster_entries: Array, main_entries: Array) -> bool:
	var path := DECKLIST_DIR + deck_name + DECK_EXTENSION
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
	var path := DECKLIST_DIR + deck_name + DECK_EXTENSION
	if not FileAccess.file_exists(path):
		return false
	DirAccess.remove_absolute(path)
	for i in range(2):
		if _player_decks[i] != null and _player_decks[i]["deck_name"] == deck_name:
			_player_decks[i] = null
	return true


# --- Internal ---

func _parse_decklist(content: String) -> Dictionary:
	var result := {"monster": [], "main": []}
	var current_section := ""

	for line in content.split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line == LINE_DELIMITER_MONSTER_DECK:
			current_section = "monster"
			continue
		if line == LINE_DELIMITER_MAIN_DECK:
			current_section = "main"
			continue
		if current_section.is_empty():
			continue

		var parts := line.split(" ", false)
		if parts.size() >= 2:
			var qty := int(parts[0])
			var card_number := parts[1].strip_edges()
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
	var content := LINE_DELIMITER_MONSTER_DECK + "
1 ESD01-001
1 ESD01-002
1 ESD01-003
1 ESD01-004

" + LINE_DELIMITER_MAIN_DECK + "
4 ESD01-005
3 ESD01-006
3 ESD01-007
8 ESD01-008
6 ESD01-009
3 ESD01-010
6 ESD01-011
4 ESD01-012
4 ESD01-013
3 ESD01-014
3 ESD01-015
3 ESD01-016"

	var path := DECKLIST_DIR + "ESD01 Starter" + DECK_EXTENSION
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
