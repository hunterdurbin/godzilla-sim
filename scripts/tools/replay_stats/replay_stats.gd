extends Node

## Headless replay-analysis CLI. Reads replay JSONs (live matches or sim
## output), computes per-turn / per-phase stats via ReplayMetrics, and writes
## a JSON + markdown report designed for an AI agent to propose BotConfig
## weight adjustments (see the knob_map in the JSON output).
##
## Run:
##   <godot> --headless --path . res://scripts/tools/replay_stats/ReplayStats.tscn \
##       -- --in user://replays/sim --out user://replay_reports --tag kaiju_v1
##
## Scene-run (not --script) because card lookups need the CardData autoload.

var input_path: String = "user://replays/sim/"
var out_dir: String = "user://replay_reports/"
var tag: String = "report"


func _ready() -> void:
	_parse_args()
	var files := _collect_replay_files(input_path)
	if files.is_empty():
		push_error("[ReplayStats] No replay JSONs found at %s" % input_path)
		get_tree().quit(1)
		return
	print("[ReplayStats] Analyzing %d replays from %s" % [files.size(), input_path])

	var games: Array = []
	for path in files:
		var replay := _load_json(path)
		if replay.is_empty():
			push_warning("[ReplayStats] Skipping unreadable replay %s" % path)
			continue
		var game := ReplayMetrics.analyze_game(replay, GameSerializer.id_to_card)
		game["file"] = path.get_file()
		games.append(game)
	if games.is_empty():
		push_error("[ReplayStats] No readable replays")
		get_tree().quit(1)
		return

	var report := ReplayMetrics.aggregate(games)
	report["source"]["path"] = input_path
	report["games"] = games

	DirAccess.make_dir_recursive_absolute(out_dir)
	var json_path := out_dir.path_join("report_%s.json" % tag)
	var md_path := out_dir.path_join("report_%s.md" % tag)
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	f = FileAccess.open(md_path, FileAccess.WRITE)
	f.store_string(ReplayMetrics.to_markdown(report, games))
	f.close()

	print("[ReplayStats] Wrote %s and %s" % [
		ProjectSettings.globalize_path(json_path), ProjectSettings.globalize_path(md_path)])
	print("[ReplayStats] Games: %d | P1 win rate: %.0f%% | Avg turns: %.1f" % [
		games.size(), report["win_rate"]["p0"] * 100.0, report["avg_turns"]])
	get_tree().quit(0)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		match args[i]:
			"--in":
				i += 1
				input_path = args[i] if i < args.size() else input_path
			"--out":
				i += 1
				out_dir = args[i] if i < args.size() else out_dir
			"--tag":
				i += 1
				tag = args[i] if i < args.size() else tag
		i += 1


func _collect_replay_files(path: String) -> Array[String]:
	var files: Array[String] = []
	if FileAccess.file_exists(path):
		files.append(path)
		return files
	var dir := DirAccess.open(path)
	if dir == null:
		return files
	for fname in dir.get_files():
		if fname.ends_with(".json"):
			files.append(path.path_join(fname))
	files.sort()
	return files


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
