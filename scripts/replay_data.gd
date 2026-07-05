class_name ReplayData
extends RefCounted

## Data class for a recorded game replay. Each snapshot captures the full game
## state at a turn boundary plus the log lines produced during that turn.

const REPLAY_DIR := "user://replays/"
const REPLAY_VERSION := 1
const MAX_RECENT_REPLAYS := 50

var version: int = REPLAY_VERSION
var game_version: String = ""
var timestamp: String = ""
var timestamp_unix: float = 0.0  # UTC unix seconds; 0 = unknown (legacy replay)
var game_seed: int = 0
var player_names: Array[String] = ["Player 1", "Player 2"]
var deck_names: Array[String] = ["", ""]
var mode: String = ""  # "solo", "solo_bot", "lan", "online"
var bot_difficulty: String = ""
var winner_id: int = -1
var win_reason: String = ""
var first_player_id: int = 0
var total_turns: int = 0
var label: String = ""
var snapshots: Array[Dictionary] = []
# Each snapshot: { turn_number, current_player_id, phase, players: [serialized x2], log_lines: [] }

## Static var for passing replay data to the viewer scene.
static var pending_replay: ReplayData = null


func to_dict() -> Dictionary:
	return {
		"version": version,
		"game_version": game_version,
		"timestamp": timestamp,
		"timestamp_unix": timestamp_unix,
		"game_seed": game_seed,
		"player_names": Array(player_names),
		"deck_names": Array(deck_names),
		"mode": mode,
		"bot_difficulty": bot_difficulty,
		"winner_id": winner_id,
		"win_reason": win_reason,
		"first_player_id": first_player_id,
		"total_turns": total_turns,
		"label": label,
		"snapshots": snapshots,
	}


func from_dict(data: Dictionary) -> void:
	version = data.get("version", 1)
	game_version = data.get("game_version", "")
	timestamp = data.get("timestamp", "")
	timestamp_unix = data.get("timestamp_unix", 0.0)
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
	label = data.get("label", "")
	var raw_snaps: Array = data.get("snapshots", [])
	snapshots = []
	for s in raw_snaps:
		snapshots.append(s)


static func local_datetime_string_from_unix(unix: float) -> String:
	## Converts a UTC unix timestamp to a "YYYY-MM-DD HH:MM:SS" string in the
	## local timezone (matching the format used by ReplayRecorder).
	var bias_seconds: int = Time.get_time_zone_from_system().bias * 60
	return Time.get_datetime_string_from_unix_time(int(unix) + bias_seconds).replace("T", " ")


# -- Versioned directory helpers --

static func _get_game_version() -> String:
	var ver: String = ProjectSettings.get_setting("application/config/version", "")
	ver = ver.replace("/", "_").replace("\\", "_").replace(":", "_") \
		.replace(" ", "_").replace("*", "_").replace("?", "_")
	return ver if not ver.is_empty() else "unknown"


static func get_version_recent_dir(ver: String) -> String:
	return REPLAY_DIR + ver + "/recent/"


static func get_version_favorites_dir(ver: String) -> String:
	return REPLAY_DIR + ver + "/favorites/"


static func _ensure_dirs() -> void:
	var ver := _get_game_version()
	DirAccess.make_dir_recursive_absolute(get_version_recent_dir(ver))
	DirAccess.make_dir_recursive_absolute(get_version_favorites_dir(ver))
	_migrate_flat_replays()


static func _migrate_flat_replays() -> void:
	var dir := DirAccess.open(REPLAY_DIR)
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
		var path := REPLAY_DIR + f
		var meta := _load_metadata_from_file(path)
		if meta.is_empty():
			continue
		var ver: String = meta.get("game_version", "")
		ver = ver.replace("/", "_").replace("\\", "_").replace(":", "_") \
			.replace(" ", "_").replace("*", "_").replace("?", "_")
		if ver.is_empty():
			ver = "unknown"
		var dest_dir := get_version_recent_dir(ver)
		DirAccess.make_dir_recursive_absolute(dest_dir)
		DirAccess.rename_absolute(path, dest_dir + f)


# -- File operations --

static func save_to_file(replay: ReplayData, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
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


static func _load_metadata_from_file(path: String) -> Dictionary:
	## Reads JSON and returns metadata dict without deserializing snapshots.
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var data: Dictionary = json.data
	var pn: Array = data.get("player_names", ["Player 1", "Player 2"])
	var dn: Array = data.get("deck_names", ["", ""])
	return {
		"timestamp": data.get("timestamp", ""),
		"player_names": [str(pn[0]) if pn.size() > 0 else "Player 1", str(pn[1]) if pn.size() > 1 else "Player 2"],
		"winner_id": data.get("winner_id", -1),
		"turns": data.get("total_turns", 0),
		"mode": data.get("mode", ""),
		"deck_names": [str(dn[0]) if dn.size() > 0 else "", str(dn[1]) if dn.size() > 1 else ""],
		"game_version": data.get("game_version", ""),
		"label": data.get("label", ""),
	}


static func list_replays() -> Array[Dictionary]:
	## Returns [{path, timestamp, player_names, winner_id, turns, mode, deck_names,
	##   game_version, label, is_favorite}] sorted newest first.
	_ensure_dirs()
	var dir := DirAccess.open(REPLAY_DIR)
	if not dir:
		return []

	var entries: Array[Dictionary] = []

	# Scan all version subdirectories
	dir.list_dir_begin()
	var ver_name := dir.get_next()
	while not ver_name.is_empty():
		if dir.current_is_dir() and not ver_name.begins_with("."):
			_scan_subdir(REPLAY_DIR + ver_name + "/recent/", false, entries)
			_scan_subdir(REPLAY_DIR + ver_name + "/favorites/", true, entries)
		ver_name = dir.get_next()
	dir.list_dir_end()

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["timestamp"] > b["timestamp"]
	)
	return entries


static func _scan_subdir(dir_path: String, is_favorite: bool, entries: Array[Dictionary]) -> void:
	var sub := DirAccess.open(dir_path)
	if not sub:
		return
	sub.list_dir_begin()
	var fname := sub.get_next()
	while not fname.is_empty():
		if fname.ends_with(".json"):
			var path := dir_path + fname
			var meta := _load_metadata_from_file(path)
			if not meta.is_empty():
				meta["path"] = path
				meta["is_favorite"] = is_favorite
				entries.append(meta)
		fname = sub.get_next()
	sub.list_dir_end()


# -- Management methods --

static func toggle_favorite(path: String) -> String:
	## Moves file between recent/ and favorites/ in the same version dir.
	## Returns the new path.
	var fname := path.get_file()
	var dir_part := path.get_base_dir()  # e.g. user://replays/1.0/recent
	var parent := dir_part.get_base_dir()  # e.g. user://replays/1.0

	var new_dir: String
	if "/favorites/" in path or dir_part.ends_with("/favorites"):
		new_dir = parent + "/recent/"
	else:
		new_dir = parent + "/favorites/"
	DirAccess.make_dir_recursive_absolute(new_dir)
	var new_path := new_dir + fname
	DirAccess.rename_absolute(path, new_path)
	return new_path


static func update_label(path: String, new_label: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	file = null  # Close read handle
	data["label"] = new_label
	var wf := FileAccess.open(path, FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(data, "\t"))


static func delete_replay(path: String) -> void:
	DirAccess.remove_absolute(path)


static func delete_all_recent() -> int:
	## Deletes all .json files in recent/ folders across all versions. Returns count.
	var dir := DirAccess.open(REPLAY_DIR)
	if not dir:
		return 0
	var count := 0
	dir.list_dir_begin()
	var ver_name := dir.get_next()
	while not ver_name.is_empty():
		if dir.current_is_dir() and not ver_name.begins_with("."):
			var recent_dir := REPLAY_DIR + ver_name + "/recent/"
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


static func prune_recent(ver: String, max_count: int = MAX_RECENT_REPLAYS) -> void:
	## Deletes oldest recent replays beyond max_count for a given version.
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
	# Filenames encode timestamp so lexicographic sort = chronological
	files.sort()
	var to_remove := files.size() - max_count
	for i in to_remove:
		DirAccess.remove_absolute(recent_dir + files[i])


static func get_replay_base_dir() -> String:
	return ProjectSettings.globalize_path(REPLAY_DIR)
