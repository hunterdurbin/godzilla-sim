extends GdUnitTestSuite

## Guard: per-card effect scripts express intent; the engine enforces the
## rules (scripts/effects/README.md § Per-card scripts). A card script that
## mutates a zone or the monster's position by hand skips the rules the
## EffectHandler primitives apply (overload, replacement effects, leave-play,
## cards_destroyed_this_turn, Revenge/standby). This test scans every per-set
## effect script directory and fails on any direct mutation. Engine modules in
## the effects root (scripts/effects/*.gd) are exempt — they ARE the engine.
##
## There is deliberately no allow-list: a missing primitive gets added to the
## engine, not exempted here.

const EFFECTS_ROOT := "res://scripts/effects"

## pattern name -> regex. Comments are stripped before matching.
const FORBIDDEN: Dictionary[String, String] = {
	"clear_zone(": "\\bclear_zone\\s*\\(",
	"push_zone_card(": "\\bpush_zone_card\\s*\\(",
	"banish_or_discard(": "\\bbanish_or_discard\\s*\\(",
	"monster_zone assignment": "\\bmonster_zone\\s*([-+*/]?=)(?!=)",
	"zones[...] write": "\\bzones\\s*\\[[^\\]]*\\]\\s*(=(?!=)|\\.\\s*(append|push_front|push_back|insert|pop_front|pop_back|pop_at|remove_at|erase|clear|resize|fill|assign|append_array|reverse|sort)\\s*\\()",
}


func _per_set_script_paths() -> Array[String]:
	var paths: Array[String] = []
	var root := DirAccess.open(EFFECTS_ROOT)
	assert_object(root).is_not_null()
	if root == null:
		return paths
	for sub in root.get_directories():
		var dir_path := "%s/%s" % [EFFECTS_ROOT, sub]
		for f in DirAccess.get_files_at(dir_path):
			if f.ends_with(".gd"):
				paths.append("%s/%s" % [dir_path, f])
	return paths


static func _strip_comment(line: String) -> String:
	# Good enough for card scripts: '#' inside string literals is not used
	# alongside the forbidden calls.
	var hash_at := line.find("#")
	return line if hash_at < 0 else line.substr(0, hash_at)


var _regexes: Dictionary[String, RegEx] = {}


func _compiled() -> Dictionary[String, RegEx]:
	if _regexes.is_empty():
		for label: String in FORBIDDEN:
			var re := RegEx.new()
			re.compile(FORBIDDEN[label])
			_regexes[label] = re
	return _regexes


func _violations_in(path: String, text: String) -> Array[String]:
	var out: Array[String] = []
	var regexes := _compiled()
	var lines := text.split("\n")
	for i in range(lines.size()):
		var code := _strip_comment(lines[i])
		for label: String in regexes:
			if regexes[label].search(code) != null:
				out.append("%s:%d  %s  ->  %s" % [path, i + 1, label, lines[i].strip_edges()])
	return out


func test_scans_a_meaningful_number_of_card_scripts() -> void:
	# Sanity: if the directory walk breaks, the guard would pass vacuously.
	assert_int(_per_set_script_paths().size()).is_greater(300)


func test_patterns_catch_known_mutations() -> void:
	var src := "\n".join([
		"var s := ctx.owner.clear_zone(3)",
		"ctx.owner.push_zone_card(2, card)",
		"EffectHandler.banish_or_discard(ctx.owner, s)",
		"ctx.owner.monster_zone = 4",
		"ctx.owner.monster_zone += 1",
		"ctx.owner.zones[dest] = stack",
		"ctx.owner.zones[i].append(card)",
	])
	assert_int(_violations_in("fake.gd", src).size()).is_equal(7)


func test_patterns_ignore_reads_and_comments() -> void:
	var src := "\n".join([
		"var idx: int = ctx.owner.monster_zone - 1",
		"if ctx.owner.monster_zone == 4:",
		"if ctx.owner.monster_zone >= 4 and ctx.owner.monster_zone != 8:",
		"var top := ctx.owner.zones[2][0]",
		"if ctx.owner.zones[i] == []:",
		"# ctx.owner.clear_zone(3) is forbidden",
		"var n := ctx.owner.get_zone_stack(zone_idx).size()",
	])
	assert_array(_violations_in("fake.gd", src)).is_empty()


func test_card_scripts_do_not_mutate_zones_or_monster_position() -> void:
	var violations: Array[String] = []
	for path in _per_set_script_paths():
		var text := FileAccess.get_file_as_string(path)
		violations.append_array(_violations_in(path, text))
	assert_array(violations) \
		.override_failure_message(
			"Card scripts must call EffectHandler primitives instead of mutating "
			+ "zones / monster position (scripts/effects/README.md § Per-card "
			+ "scripts). Violations:\n" + "\n".join(violations)) \
		.is_empty()
