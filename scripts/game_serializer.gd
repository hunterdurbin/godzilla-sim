class_name GameSerializer
extends RefCounted

## Shared serialization helpers for replay recording, save/load, and replay viewer.
## Converts between PlayerState objects and plain Dictionaries using card IDs.


static func card_to_id(card: Dictionary) -> String:
	return card.get("id", "")


static func cards_to_ids(cards: Array) -> Array:
	var ids: Array = []
	for c in cards:
		ids.append(c.get("id", "") if c is Dictionary else "")
	return ids


static func id_to_card(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	var base_id := instance_id
	var underscore_pos := instance_id.find("_")
	if underscore_pos != -1:
		base_id = instance_id.substr(0, underscore_pos)
	var template := CardData.get_card_by_id(base_id)
	if template.is_empty():
		return {}
	var card := template.duplicate()
	card["id"] = instance_id
	return card


static func ids_to_cards(ids: Array) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for id in ids:
		var card := id_to_card(str(id))
		if not card.is_empty():
			cards.append(card)
	return cards


static func serialize_player_state(ps: PlayerState) -> Dictionary:
	var zone_ids: Array = []
	for zone_stack in ps.zones:
		zone_ids.append(cards_to_ids(zone_stack))
	var strat_ids: Array = []
	for s in ps.strategy_zones:
		strat_ids.append(card_to_id(s) if s is Dictionary else "")
	# Cards stacked under each strategy (e.g. EBP04-089 RAGE markers).
	var strat_stack_ids: Array = []
	for stack in ps.strategy_zone_stacks:
		strat_stack_ids.append(cards_to_ids(stack) if stack is Array else [])
	return {
		"player_id": ps.player_id,
		"monster_zone": ps.monster_zone,
		"rage": ps.rage,
		"current_monster": card_to_id(ps.current_monster),
		"zones": zone_ids,
		"strategy_zones": strat_ids,
		"strategy_zone_stacks": strat_stack_ids,
		"hand": cards_to_ids(ps.hand),
		"hand_count": ps.hand.size(),
		"main_deck": cards_to_ids(ps.main_deck),
		"main_deck_count": ps.main_deck.size(),
		"discard_pile": cards_to_ids(ps.discard_pile),
		"discard_pile_count": ps.discard_pile.size(),
		"has_invaded_this_turn": ps.has_invaded_this_turn,
		"has_played_monster_this_turn": ps.has_played_monster_this_turn,
		"monster_stack": cards_to_ids(ps.monster_stack),
		"burst_monster": card_to_id(ps.burst_monster),
		"pre_burst_monster": card_to_id(ps.pre_burst_monster),
		"monster_deck": cards_to_ids(ps.monster_deck),
		"strategy_zone_turn_placed": ps.strategy_zone_turn_placed.duplicate(),
		"invasion_zones_crossed": ps.invasion_zones_crossed,
		"last_invasion_card": card_to_id(ps.last_invasion_card),
		"cards_destroyed_this_turn": cards_to_ids(ps.cards_destroyed_this_turn),
	}


static func deserialize_to_player_state(data: Dictionary) -> PlayerState:
	var ps := PlayerState.new(data.get("player_id", 0))

	ps.monster_zone = data.get("monster_zone", 1)
	ps.rage = data.get("rage", 0)
	ps.has_invaded_this_turn = data.get("has_invaded_this_turn", false)
	ps.has_played_monster_this_turn = data.get("has_played_monster_this_turn", false)
	ps.invasion_zones_crossed = data.get("invasion_zones_crossed", 0)

	# Reconstruct card dictionaries from IDs
	ps.current_monster = id_to_card(data.get("current_monster", ""))
	ps.burst_monster = id_to_card(data.get("burst_monster", ""))
	ps.pre_burst_monster = id_to_card(data.get("pre_burst_monster", ""))
	ps.hand = Array(ids_to_cards(data.get("hand", [])), TYPE_DICTIONARY, "", null)
	ps.main_deck = Array(ids_to_cards(data.get("main_deck", [])), TYPE_DICTIONARY, "", null)
	ps.discard_pile = Array(ids_to_cards(data.get("discard_pile", [])), TYPE_DICTIONARY, "", null)
	ps.monster_deck = Array(ids_to_cards(data.get("monster_deck", [])), TYPE_DICTIONARY, "", null)
	ps.monster_stack = Array(ids_to_cards(data.get("monster_stack", [])), TYPE_DICTIONARY, "", null)
	ps.last_invasion_card = id_to_card(str(data.get("last_invasion_card", "")))
	ps.cards_destroyed_this_turn = Array(ids_to_cards(data.get("cards_destroyed_this_turn", [])), TYPE_DICTIONARY, "", null)

	# Zones: array of 8 zone stacks
	var zone_ids: Array = data.get("zones", [])
	for i in range(8):
		if i < zone_ids.size():
			ps.zones[i] = Array(ids_to_cards(zone_ids[i]))
		else:
			ps.zones[i] = []

	# Strategy zones
	var strat_ids: Array = data.get("strategy_zones", [])
	var strat_count := maxi(strat_ids.size(), 2)
	ps.strategy_zones.resize(strat_count)
	for i in range(strat_count):
		if i < strat_ids.size() and not str(strat_ids[i]).is_empty():
			ps.strategy_zones[i] = id_to_card(str(strat_ids[i]))
		else:
			ps.strategy_zones[i] = {}

	# Strategy zone turn placed
	var sztp: Array = data.get("strategy_zone_turn_placed", [0, 0])
	ps.strategy_zone_turn_placed.resize(strat_count)
	for i in range(strat_count):
		ps.strategy_zone_turn_placed[i] = sztp[i] if i < sztp.size() else 0

	# Cards stacked under each strategy (EBP04-089 RAGE markers)
	var szs_data: Array = data.get("strategy_zone_stacks", [])
	ps.strategy_zone_stacks.resize(strat_count)
	for i in range(strat_count):
		ps.strategy_zone_stacks[i] = Array(ids_to_cards(szs_data[i])) if i < szs_data.size() else []

	return ps


# --- Save/Load game helpers ---

const SAVE_DIR := "user://saves/"
const MAX_RECENT_SAVES := 50

## Static var for passing loaded save data to GameBoard.
static var pending_load: Dictionary = {}


static func serialize_game_state(gs: GameState, first_player_id: int, mode: String, bot_difficulty: String, deck_names: Array[String], game_seed: int = 0) -> Dictionary:
	return {
		"version": 1,
		"game_version": ProjectSettings.get_setting("application/config/version", ""),
		"timestamp": Time.get_datetime_string_from_system(false, true).replace("T", " "),
		"turn_number": gs.turn_number,
		"current_player_id": gs.current_player_id,
		"current_phase": int(gs.current_phase),
		"current_sub_phase": gs.current_sub_phase,
		"player_names": Array(gs.player_names),
		"first_player_id": first_player_id,
		"mode": mode,
		"bot_difficulty": bot_difficulty,
		"deck_names": Array(deck_names),
		"game_seed": game_seed,
		"label": "",
		"players": [
			serialize_player_state(gs.players[0]),
			serialize_player_state(gs.players[1]),
		],
	}


# -- Versioned directory helpers --

static func _get_game_version() -> String:
	var ver: String = ProjectSettings.get_setting("application/config/version", "")
	ver = ver.replace("/", "_").replace("\\", "_").replace(":", "_") \
		.replace(" ", "_").replace("*", "_").replace("?", "_")
	return ver if not ver.is_empty() else "unknown"


static func get_version_recent_dir(ver: String) -> String:
	return SAVE_DIR + ver + "/recent/"


static func get_version_favorites_dir(ver: String) -> String:
	return SAVE_DIR + ver + "/favorites/"


static func _ensure_save_dirs() -> void:
	var ver := _get_game_version()
	DirAccess.make_dir_recursive_absolute(get_version_recent_dir(ver))
	DirAccess.make_dir_recursive_absolute(get_version_favorites_dir(ver))
	_migrate_flat_saves()


static func _migrate_flat_saves() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	var files_to_migrate: Array[String] = []
	while not fname.is_empty():
		if fname.ends_with(".json"):
			files_to_migrate.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()

	for f in files_to_migrate:
		var path := SAVE_DIR + f
		var data := load_save_file(path)
		if data.is_empty():
			continue
		var ver: String = data.get("game_version", "")
		ver = ver.replace("/", "_").replace("\\", "_").replace(":", "_") \
			.replace(" ", "_").replace("*", "_").replace("?", "_")
		if ver.is_empty():
			ver = "unknown"
		var dest_dir := get_version_recent_dir(ver)
		DirAccess.make_dir_recursive_absolute(dest_dir)
		DirAccess.rename_absolute(path, dest_dir + f)


# -- File operations --

static func save_game_to_file(data: Dictionary) -> String:
	var ver := _get_game_version()
	var ts: String = data.get("timestamp", "").replace(" ", "_").replace(":", "").replace("-", "")
	var fname := "save_%s.json" % ts
	var path := get_version_recent_dir(ver) + fname
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_warning("GameSerializer: Failed to save game to %s" % path)
		return ""
	file.store_string(JSON.stringify(data, "\t"))
	print("[Save] Game saved to %s" % path)
	prune_recent_saves(ver)
	return path


static func load_save_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data


static func _load_save_metadata(path: String) -> Dictionary:
	## Reads JSON and returns metadata dict without full deserialization.
	var data := load_save_file(path)
	if data.is_empty():
		return {}
	var pn: Array = data.get("player_names", ["?", "?"])
	var dn: Array = data.get("deck_names", ["", ""])
	return {
		"timestamp": data.get("timestamp", ""),
		"player_names": [str(pn[0]) if pn.size() > 0 else "?", str(pn[1]) if pn.size() > 1 else "?"],
		"turn_number": data.get("turn_number", 0),
		"mode": data.get("mode", ""),
		"deck_names": [str(dn[0]) if dn.size() > 0 else "", str(dn[1]) if dn.size() > 1 else ""],
		"game_version": data.get("game_version", ""),
		"label": data.get("label", ""),
	}


static func list_saves() -> Array[Dictionary]:
	## Returns [{path, timestamp, player_names, turn_number, mode, deck_names,
	##   game_version, label, is_favorite}] sorted newest first.
	_ensure_save_dirs()
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return []

	var entries: Array[Dictionary] = []

	dir.list_dir_begin()
	var ver_name := dir.get_next()
	while not ver_name.is_empty():
		if dir.current_is_dir() and not ver_name.begins_with("."):
			_scan_save_subdir(SAVE_DIR + ver_name + "/recent/", false, entries)
			_scan_save_subdir(SAVE_DIR + ver_name + "/favorites/", true, entries)
		ver_name = dir.get_next()
	dir.list_dir_end()

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["timestamp"] > b["timestamp"]
	)
	return entries


static func _scan_save_subdir(dir_path: String, is_favorite: bool, entries: Array[Dictionary]) -> void:
	var sub := DirAccess.open(dir_path)
	if not sub:
		return
	sub.list_dir_begin()
	var fname := sub.get_next()
	while not fname.is_empty():
		if fname.ends_with(".json"):
			var path := dir_path + fname
			var meta := _load_save_metadata(path)
			if not meta.is_empty():
				meta["path"] = path
				meta["is_favorite"] = is_favorite
				entries.append(meta)
		fname = sub.get_next()
	sub.list_dir_end()


# -- Management methods --

static func toggle_save_favorite(path: String) -> String:
	## Moves file between recent/ and favorites/. Returns the new path.
	var fname := path.get_file()
	var dir_part := path.get_base_dir()
	var parent := dir_part.get_base_dir()

	var new_dir: String
	if "/favorites/" in path or dir_part.ends_with("/favorites"):
		new_dir = parent + "/recent/"
	else:
		new_dir = parent + "/favorites/"
	DirAccess.make_dir_recursive_absolute(new_dir)
	var new_path := new_dir + fname
	DirAccess.rename_absolute(path, new_path)
	return new_path


static func update_save_label(path: String, new_label: String) -> void:
	var data := load_save_file(path)
	if data.is_empty():
		return
	data["label"] = new_label
	var wf := FileAccess.open(path, FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(data, "\t"))


static func delete_save(path: String) -> void:
	DirAccess.remove_absolute(path)


static func delete_all_recent_saves() -> int:
	## Deletes all .json in recent/ folders across all versions. Returns count.
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return 0
	var count := 0
	dir.list_dir_begin()
	var ver_name := dir.get_next()
	while not ver_name.is_empty():
		if dir.current_is_dir() and not ver_name.begins_with("."):
			var recent_dir := SAVE_DIR + ver_name + "/recent/"
			var sub := DirAccess.open(recent_dir)
			if sub:
				sub.list_dir_begin()
				var fname := sub.get_next()
				while not fname.is_empty():
					if fname.ends_with(".json"):
						DirAccess.remove_absolute(recent_dir + fname)
						count += 1
					fname = sub.get_next()
				sub.list_dir_end()
		ver_name = dir.get_next()
	dir.list_dir_end()
	return count


static func prune_recent_saves(ver: String, max_count: int = MAX_RECENT_SAVES) -> void:
	## Deletes oldest recent saves beyond max_count for a given version.
	var recent_dir := get_version_recent_dir(ver)
	var sub := DirAccess.open(recent_dir)
	if not sub:
		return
	var files: Array[String] = []
	sub.list_dir_begin()
	var fname := sub.get_next()
	while not fname.is_empty():
		if fname.ends_with(".json"):
			files.append(fname)
		fname = sub.get_next()
	sub.list_dir_end()

	if files.size() <= max_count:
		return
	files.sort()
	var to_remove := files.size() - max_count
	for i in to_remove:
		DirAccess.remove_absolute(recent_dir + files[i])


static func get_save_base_dir() -> String:
	return ProjectSettings.globalize_path(SAVE_DIR)
