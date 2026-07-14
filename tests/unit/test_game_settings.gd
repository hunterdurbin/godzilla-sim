extends GdUnitTestSuite

## SteamOS auto-fullscreen must yield to Godot's built-in display flags.
## The engine consumes those flags before OS.get_cmdline_args() sees them,
## so GameSettings reads the raw argv (/proc/self/cmdline on Linux) and
## matches against this list — keep it in sync with Godot's CLI options.


func test_contains_display_flag_matches_all_display_options() -> void:
	for flag: String in [
		"-f", "--fullscreen", "-w", "--windowed", "-m", "--maximized",
		"--resolution", "--position",
	]:
		var argv := PackedStringArray(["game_binary", flag])
		assert_bool(GameSettings.contains_display_flag(argv)) \
				.override_failure_message("expected %s to be detected" % flag).is_true()


func test_contains_display_flag_ignores_other_args() -> void:
	var argv := PackedStringArray([
		"game_binary", "--path", "/some/where", "-s", "res://script.gd",
		"--verbose", "--", "--fullscreen-ish",
	])
	assert_bool(GameSettings.contains_display_flag(argv)).is_false()


func test_contains_display_flag_empty_argv() -> void:
	assert_bool(GameSettings.contains_display_flag(PackedStringArray())).is_false()


func test_parse_null_separated_argv_proc_cmdline_format() -> void:
	# /proc/self/cmdline is NUL-separated with a trailing NUL.
	var raw := _null_separated(["game_binary", "--windowed"])
	assert_that(GameSettings.parse_null_separated_argv(raw)) \
			.is_equal(PackedStringArray(["game_binary", "--windowed"]))


func test_parse_null_separated_argv_no_trailing_null() -> void:
	var raw := _null_separated(["game_binary", "--resolution", "1920x1080"])
	raw.resize(raw.size() - 1)
	assert_that(GameSettings.parse_null_separated_argv(raw)) \
			.is_equal(PackedStringArray(["game_binary", "--resolution", "1920x1080"]))


func test_parse_null_separated_argv_empty() -> void:
	assert_that(GameSettings.parse_null_separated_argv(PackedByteArray())) \
			.is_equal(PackedStringArray())


func _null_separated(tokens: Array[String]) -> PackedByteArray:
	var raw := PackedByteArray()
	for token in tokens:
		raw.append_array(token.to_utf8_buffer())
		raw.append(0)
	return raw
