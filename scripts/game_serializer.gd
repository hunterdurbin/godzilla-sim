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
	return {
		"player_id": ps.player_id,
		"monster_zone": ps.monster_zone,
		"rage": ps.rage,
		"current_monster": card_to_id(ps.current_monster),
		"zones": zone_ids,
		"strategy_zones": strat_ids,
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

	return ps


# --- Save/Load game helpers ---

const SAVE_DIR := "user://saves/"

## Static var for passing loaded save data to GameBoard.
static var pending_load: Dictionary = {}


static func serialize_game_state(gs: GameState, first_player_id: int, mode: String, bot_difficulty: String, deck_names: Array[String]) -> Dictionary:
	return {
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(false, true).replace("T", " "),
		"turn_number": gs.turn_number,
		"current_player_id": gs.current_player_id,
		"current_phase": int(gs.current_phase),
		"player_names": Array(gs.player_names),
		"first_player_id": first_player_id,
		"mode": mode,
		"bot_difficulty": bot_difficulty,
		"deck_names": Array(deck_names),
		"players": [
			serialize_player_state(gs.players[0]),
			serialize_player_state(gs.players[1]),
		],
	}


static func save_game_to_file(data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var ts: String = data.get("timestamp", "").replace(" ", "_").replace(":", "").replace("-", "")
	var fname := "save_%s.json" % ts
	var path := SAVE_DIR + fname
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_warning("GameSerializer: Failed to save game to %s" % path)
		return ""
	file.store_string(JSON.stringify(data, "\t"))
	print("[Save] Game saved to %s" % path)
	return path


static func load_save_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data


static func list_saves() -> Array[Dictionary]:
	## Returns [{path, timestamp, player_names, turn_number, mode}] sorted newest first.
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return []
	var entries: Array[Dictionary] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".json"):
			var path := SAVE_DIR + fname
			var data := load_save_file(path)
			if not data.is_empty():
				var pn: Array = data.get("player_names", ["?", "?"])
				entries.append({
					"path": path,
					"timestamp": data.get("timestamp", ""),
					"player_names": pn,
					"turn_number": data.get("turn_number", 0),
					"mode": data.get("mode", ""),
				})
		fname = dir.get_next()
	dir.list_dir_end()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["timestamp"] > b["timestamp"]
	)
	return entries
