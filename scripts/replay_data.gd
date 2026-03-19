class_name ReplayData
extends RefCounted

## Data class for a recorded game replay. Each snapshot captures the full game
## state at a turn boundary plus the log lines produced during that turn.

const REPLAY_DIR := "user://replays/"
const REPLAY_VERSION := 1

var version: int = REPLAY_VERSION
var game_version: String = ""
var timestamp: String = ""
var game_seed: int = 0
var player_names: Array[String] = ["Player 1", "Player 2"]
var deck_names: Array[String] = ["", ""]
var mode: String = ""  # "solo", "solo_bot", "lan", "online"
var bot_difficulty: String = ""
var winner_id: int = -1
var win_reason: String = ""
var first_player_id: int = 0
var total_turns: int = 0
var snapshots: Array[Dictionary] = []
# Each snapshot: { turn_number, current_player_id, phase, players: [serialized x2], log_lines: [] }

## Static var for passing replay data to the viewer scene.
static var pending_replay: ReplayData = null


func to_dict() -> Dictionary:
	return {
		"version": version,
		"game_version": game_version,
		"timestamp": timestamp,
		"game_seed": game_seed,
		"player_names": Array(player_names),
		"deck_names": Array(deck_names),
		"mode": mode,
		"bot_difficulty": bot_difficulty,
		"winner_id": winner_id,
		"win_reason": win_reason,
		"first_player_id": first_player_id,
		"total_turns": total_turns,
		"snapshots": snapshots,
	}


func from_dict(data: Dictionary) -> void:
	version = data.get("version", 1)
	game_version = data.get("game_version", "")
	timestamp = data.get("timestamp", "")
	game_seed = data.get("game_seed", 0)
	var pn: Array = data.get("player_names", ["Player 1", "Player 2"])
	player_names = [str(pn[0]) if pn.size() > 0 else "Player 1", str(pn[1]) if pn.size() > 1 else "Player 2"]
	var dn: Array = data.get("deck_names", ["", ""])
	deck_names = [str(dn[0]) if dn.size() > 0 else "", str(dn[1]) if dn.size() > 1 else ""]
	mode = data.get("mode", "")
	bot_difficulty = data.get("bot_difficulty", "")
	winner_id = data.get("winner_id", -1)
	win_reason = data.get("win_reason", "")
	first_player_id = data.get("first_player_id", 0)
	total_turns = data.get("total_turns", 0)
	var raw_snaps: Array = data.get("snapshots", [])
	snapshots = []
	for s in raw_snaps:
		snapshots.append(s)


static func save_to_file(replay: ReplayData, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(replay.to_dict(), "\t"))
	return OK


static func load_from_file(path: String) -> ReplayData:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return null
	var data: Dictionary = json.data
	var replay := ReplayData.new()
	replay.from_dict(data)
	return replay


static func list_replays() -> Array[Dictionary]:
	## Returns [{path, timestamp, player_names, winner, turns, mode}] sorted newest first.
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var dir := DirAccess.open(REPLAY_DIR)
	if not dir:
		return []
	var entries: Array[Dictionary] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".json"):
			var path := REPLAY_DIR + fname
			var replay := load_from_file(path)
			if replay:
				entries.append({
					"path": path,
					"timestamp": replay.timestamp,
					"player_names": replay.player_names,
					"winner_id": replay.winner_id,
					"turns": replay.total_turns,
					"mode": replay.mode,
					"deck_names": replay.deck_names,
				})
		fname = dir.get_next()
	dir.list_dir_end()
	# Sort newest first
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["timestamp"] > b["timestamp"]
	)
	return entries


static func delete_replay(path: String) -> void:
	DirAccess.remove_absolute(path)
