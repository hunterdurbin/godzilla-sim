class_name GameLogExport
extends RefCounted

## Exports the in-game log to plain-text files under user://game_logs/.
## Entries are GameLog token Dictionaries or raw Strings (same shape as
## LogChat.log_tokens); rendering matches BugReport.build_body.

const LOG_DIR := "user://game_logs/"


static func get_log_base_dir() -> String:
	return ProjectSettings.globalize_path(LOG_DIR)


## Renders every log entry to plain text and writes a timestamped file.
## Returns the saved path, or "" on failure.
static func export_log(log_tokens: Array) -> String:
	var err := DirAccess.make_dir_recursive_absolute(LOG_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("GameLogExport: failed to create log dir (%s)" % err)
		return ""
	var lines: Array[String] = []
	for entry in log_tokens:
		if typeof(entry) == TYPE_DICTIONARY:
			lines.append(GameLog.render_plain(entry))
		else:
			lines.append(GameLog.to_plain_text(str(entry)))
	var path := _unique_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GameLogExport: failed to open %s for writing (%s)" % [path, FileAccess.get_open_error()])
		return ""
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return path


## Lists exported logs, newest first.
## Each entry: { "path": String, "filename": String, "modified_unix": int }
static func list_logs() -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return logs
	for filename in dir.get_files():
		if not filename.ends_with(".txt"):
			continue
		var path := LOG_DIR + filename
		logs.append({
			"path": path,
			"filename": filename,
			"modified_unix": FileAccess.get_modified_time(path),
		})
	logs.sort_custom(func(a, b): return a["modified_unix"] > b["modified_unix"])
	return logs


static func load_log_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


static func _unique_path() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := LOG_DIR + "game_log_%s.txt" % stamp
	var suffix := 2
	while FileAccess.file_exists(path):
		path = LOG_DIR + "game_log_%s_%d.txt" % [stamp, suffix]
		suffix += 1
	return path
