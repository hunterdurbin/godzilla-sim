extends Node
## Autoload singleton: manages deck list files and selected deck state.
##
## Decks live under DECKLIST_DIR as <DeckName>.deck files. Folders are real
## subdirectories under DECKLIST_DIR (e.g. user://decklists/Iterations/Foo.deck).
## Deck names remain globally unique across folders so existing call sites that
## key by bare deck name (bot_deck_weights, last_selected_deck, replay metadata,
## lobby code paths) keep working unchanged.

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
	## Recursive scan: returns all deck names (sorted), regardless of folder.
	var names: Array[String] = []
	var seen: Dictionary = {}
	_collect_decklist_names(DECKLIST_DIR, names, seen)
	names.sort()
	return names


func get_all_deck_entries() -> Array[Dictionary]:
	## Returns [{"name": <deck_name>, "folder": <relative folder path or "">}, ...].
	## Folder paths use "/" as separator and never have a trailing slash.
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	_collect_decklist_entries(DECKLIST_DIR, "", entries, seen)
	entries.sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
	return entries


func get_all_folders() -> Array[String]:
	## Returns sorted list of folder paths (relative to DECKLIST_DIR).
	## Excludes the root "".
	var folders: Array[String] = []
	_collect_folder_paths(DECKLIST_DIR, "", folders)
	folders.sort()
	return folders


func get_deck_folder(deck_name: String) -> String:
	## Returns the folder a deck lives in, or "" if at the root / not found.
	var path := _find_decklist_path(deck_name)
	if path.is_empty():
		return ""
	# Strip DECKLIST_DIR prefix + filename suffix → leaves "" or "Foo/Bar".
	var rel := path.trim_prefix(DECKLIST_DIR)
	var slash := rel.rfind("/")
	if slash < 0:
		return ""
	return rel.substr(0, slash)


func load_decklist(deck_name: String) -> Dictionary:
	var path := _find_decklist_path(deck_name)
	if path.is_empty():
		return {}
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


func save_decklist(deck_name: String, monster_entries: Array, main_entries: Array, folder: String = "") -> bool:
	## Save deck to the given folder (relative to DECKLIST_DIR; "" = root).
	## Backward compat: if a deck with the same name already exists somewhere
	## else and no explicit folder was passed, save it where it currently lives.
	var sanitized_name := sanitize_filename(deck_name)
	if sanitized_name.is_empty():
		return false

	var target_folder := _sanitize_folder_path(folder)
	if folder.is_empty():
		# No explicit folder — preserve the existing deck's location if any.
		var existing := _find_decklist_path(deck_name)
		if not existing.is_empty():
			var rel := existing.trim_prefix(DECKLIST_DIR)
			var slash := rel.rfind("/")
			if slash >= 0:
				target_folder = rel.substr(0, slash)

	# Collision check: same deck name in a different folder.
	var existing_path := _find_decklist_path(deck_name)
	var target_path := _build_deck_path(deck_name, target_folder)
	if not existing_path.is_empty() and existing_path != target_path:
		# Remove the stale copy before writing the new one.
		DirAccess.remove_absolute(existing_path)

	if not target_folder.is_empty():
		DirAccess.make_dir_recursive_absolute(DECKLIST_DIR + target_folder)

	var file := FileAccess.open(target_path, FileAccess.WRITE)
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
	var path := _find_decklist_path(deck_name)
	if path.is_empty():
		return false
	var folder := get_deck_folder(deck_name)
	DirAccess.remove_absolute(path)
	_cleanup_empty_folder_chain(folder)
	for i in range(2):
		if _player_decks[i] != null and _player_decks[i]["deck_name"] == deck_name:
			_player_decks[i] = null
	# Drop any bot-deck weight entry so the random-pool list stays in sync
	if GameSettings.bot_deck_weights.has(deck_name):
		GameSettings.bot_deck_weights.erase(deck_name)
		GameSettings.save()
	return true


func move_decklist(deck_name: String, target_folder: String) -> bool:
	## Move a deck file to a new folder. Returns false on collision or I/O failure.
	var src := _find_decklist_path(deck_name)
	if src.is_empty():
		return false
	var source_folder := get_deck_folder(deck_name)
	var sanitized_folder := _sanitize_folder_path(target_folder)
	var dst := _build_deck_path(deck_name, sanitized_folder)
	if src == dst:
		return true
	if FileAccess.file_exists(dst):
		# Different file already at destination — refuse to overwrite.
		return false
	if not sanitized_folder.is_empty():
		DirAccess.make_dir_recursive_absolute(DECKLIST_DIR + sanitized_folder)
	var err := DirAccess.rename_absolute(src, dst)
	if err == OK and source_folder != sanitized_folder:
		_cleanup_empty_folder_chain(source_folder)
	return err == OK


func _cleanup_empty_folder_chain(folder_path: String) -> void:
	## Walks up from folder_path toward DECKLIST_DIR removing any empty
	## directories. Stops at the first non-empty parent.
	var current := folder_path
	while not current.is_empty():
		var full := DECKLIST_DIR + current
		if not DirAccess.dir_exists_absolute(full):
			break
		if not _is_dir_empty(full):
			break
		DirAccess.remove_absolute(full)
		# Also drop any bot folder weight pinned to this folder.
		if GameSettings.bot_folder_weights.has(current):
			GameSettings.bot_folder_weights.erase(current)
			GameSettings.save()
		var slash := current.rfind("/")
		if slash < 0:
			break
		current = current.substr(0, slash)


static func _is_dir_empty(dir_path: String) -> bool:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return true
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f != "." and f != "..":
			return false
		f = dir.get_next()
	return true


func rename_folder(old_path: String, new_path: String) -> bool:
	var old_full := DECKLIST_DIR + _sanitize_folder_path(old_path)
	var new_full := DECKLIST_DIR + _sanitize_folder_path(new_path)
	if not DirAccess.dir_exists_absolute(old_full):
		return false
	if DirAccess.dir_exists_absolute(new_full):
		return false
	var err := DirAccess.rename_absolute(old_full, new_full)
	return err == OK


func delete_folder(folder_path: String, recursive: bool) -> bool:
	var sanitized := _sanitize_folder_path(folder_path)
	if sanitized.is_empty():
		return false
	var full := DECKLIST_DIR + sanitized
	if not DirAccess.dir_exists_absolute(full):
		return false
	if recursive:
		_remove_dir_recursive(full)
		return true
	# Non-recursive: only allow when empty.
	var dir := DirAccess.open(full)
	if dir == null:
		return false
	dir.list_dir_begin()
	var any := false
	var f := dir.get_next()
	while f != "":
		if f != "." and f != "..":
			any = true
			break
		f = dir.get_next()
	if any:
		return false
	DirAccess.remove_absolute(full)
	return true


func get_decklist_thumbnail_card_id(deck_name: String) -> String:
	## Returns the card id of the highest-rank monster in the deck, or "" if none.
	var data := load_decklist(deck_name)
	if data.is_empty():
		return ""
	var best_rank := -1
	var best_id := ""
	for entry in data["monster"]:
		var tpl: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		var rank: int = tpl.get("rank", -1)
		if rank > best_rank:
			best_rank = rank
			best_id = entry["card_number"]
	return best_id


static func sanitize_filename(file_name: String) -> String:
	## Remove characters illegal in Windows filenames: \ / : * ? " < > |
	return file_name.replace("\\", "_").replace("/", "_").replace(":", "-") \
		.replace("*", "_").replace("?", "_").replace("\"", "'") \
		.replace("<", "_").replace(">", "_").replace("|", "_")


# --- Internal ---

static func _sanitize_folder_path(folder: String) -> String:
	## Splits on "/", sanitizes each segment, strips empties.
	var raw := folder.strip_edges()
	if raw.is_empty():
		return ""
	var parts: Array[String] = []
	for seg in raw.split("/", false):
		var trimmed := seg.strip_edges()
		if trimmed.is_empty():
			continue
		parts.append(sanitize_filename(trimmed))
	return "/".join(parts)


func _build_deck_path(deck_name: String, folder: String) -> String:
	var sanitized := sanitize_filename(deck_name)
	if folder.is_empty():
		return DECKLIST_DIR + sanitized + DECK_EXTENSION
	return DECKLIST_DIR + folder + "/" + sanitized + DECK_EXTENSION


func _find_decklist_path(deck_name: String) -> String:
	## Locates <deck_name>.deck anywhere under DECKLIST_DIR.
	## Prefers root, then alphabetical-first folder match.
	var sanitized := sanitize_filename(deck_name)
	var root_path := DECKLIST_DIR + sanitized + DECK_EXTENSION
	if FileAccess.file_exists(root_path):
		return root_path
	var folders := get_all_folders()
	for folder in folders:
		var p := DECKLIST_DIR + folder + "/" + sanitized + DECK_EXTENSION
		if FileAccess.file_exists(p):
			return p
	return ""


func _collect_decklist_names(dir_path: String, out: Array[String], seen: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f == "." or f == "..":
			f = dir.get_next()
			continue
		var full := dir_path.path_join(f)
		if dir.current_is_dir():
			_collect_decklist_names(full, out, seen)
		elif f.ends_with(DECK_EXTENSION):
			var deck_name := f.trim_suffix(DECK_EXTENSION)
			if not seen.has(deck_name):
				seen[deck_name] = true
				out.append(deck_name)
		f = dir.get_next()


func _collect_decklist_entries(dir_path: String, rel_folder: String, out: Array[Dictionary], seen: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f == "." or f == "..":
			f = dir.get_next()
			continue
		var full := dir_path.path_join(f)
		if dir.current_is_dir():
			var sub := f if rel_folder.is_empty() else (rel_folder + "/" + f)
			_collect_decklist_entries(full, sub, out, seen)
		elif f.ends_with(DECK_EXTENSION):
			var deck_name := f.trim_suffix(DECK_EXTENSION)
			if not seen.has(deck_name):
				seen[deck_name] = true
				out.append({"name": deck_name, "folder": rel_folder})
		f = dir.get_next()


func _collect_folder_paths(dir_path: String, rel: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f == "." or f == "..":
			f = dir.get_next()
			continue
		if dir.current_is_dir():
			var sub := f if rel.is_empty() else (rel + "/" + f)
			out.append(sub)
			_collect_folder_paths(dir_path.path_join(f), sub, out)
		f = dir.get_next()


func _remove_dir_recursive(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f == "." or f == "..":
			f = dir.get_next()
			continue
		var full := dir_path.path_join(f)
		if dir.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		f = dir.get_next()
	DirAccess.remove_absolute(dir_path)


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
