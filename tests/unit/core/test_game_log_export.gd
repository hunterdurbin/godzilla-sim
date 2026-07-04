extends GdUnitTestSuite

## Tests for GameLogExport: plain-text export, listing, and round-trip read
## of the in-game log (token Dictionaries + raw String entries).

var _created_paths: Array[String] = []


func after() -> void:
	for path in _created_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _sample_tokens() -> Array:
	return [
		GameLog.turn_start(1, 0),
		"Pre-formatted system line",
		GameLog.log_exported(0, "previous_log.txt"),
	]


func test_export_creates_readable_file() -> void:
	var path := GameLogExport.export_log(_sample_tokens())
	_created_paths.append(path)

	assert_str(path).is_not_empty()
	assert_bool(FileAccess.file_exists(path)).is_true()

	var text := GameLogExport.load_log_text(path)
	var lines := text.strip_edges().split("\n")
	assert_int(lines.size()).is_equal(3)
	assert_str(lines[0]).is_equal(GameLog.render_plain(GameLog.turn_start(1, 0)))
	assert_str(lines[1]).is_equal("Pre-formatted system line")


func test_export_empty_log_produces_file() -> void:
	var path := GameLogExport.export_log([])
	_created_paths.append(path)
	assert_str(path).is_not_empty()
	assert_bool(FileAccess.file_exists(path)).is_true()


func test_repeat_exports_get_distinct_paths() -> void:
	var first := GameLogExport.export_log(_sample_tokens())
	var second := GameLogExport.export_log(_sample_tokens())
	_created_paths.append(first)
	_created_paths.append(second)
	assert_str(second).is_not_equal(first)
	assert_bool(FileAccess.file_exists(second)).is_true()


func test_list_logs_includes_exported_file() -> void:
	var path := GameLogExport.export_log(_sample_tokens())
	_created_paths.append(path)

	var filenames: Array[String] = []
	for entry in GameLogExport.list_logs():
		filenames.append(entry["filename"])
	assert_array(filenames).contains([path.get_file()])


func test_load_missing_file_returns_empty() -> void:
	assert_str(GameLogExport.load_log_text("user://game_logs/nope.txt")).is_empty()


func test_log_exported_token_renders_player_and_file() -> void:
	var rendered := GameLog.render_plain(GameLog.log_exported(0, "game_log_x.txt"))
	assert_str(rendered).contains(GameLog.player_name(0))
	assert_str(rendered).contains("game_log_x.txt")
