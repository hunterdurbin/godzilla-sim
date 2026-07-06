extends GdUnitTestSuite

## GlyphDB — the static controller-glyph lookup. Guards the asset slice:
## every controller type must ship every physical-position glyph file, and
## the joy-name detection table must route known pads to the right set.


func test_every_type_resolves_every_physical_glyph() -> void:
	for type: String in GlyphDB.TYPES:
		for physical: StringName in GlyphDB.FILE_FOR_PHYSICAL:
			var tex := GlyphDB.get_texture(type, physical)
			assert_object(tex) \
				.override_failure_message("Missing glyph for %s/%s" % [type, physical]) \
				.is_not_null()


func test_unknown_physical_returns_null() -> void:
	assert_object(GlyphDB.get_texture("xbox", &"controller_nonexistent")).is_null()


func test_unknown_type_falls_back_to_generic() -> void:
	var generic := GlyphDB.get_texture("generic", &"controller_face_south")
	var fallback := GlyphDB.get_texture("gamecube", &"controller_face_south")
	assert_object(fallback).is_same(generic)


func test_detect_type_known_names() -> void:
	assert_str(GlyphDB.detect_type("Xbox Series X Controller")).is_equal("xbox")
	assert_str(GlyphDB.detect_type("XInput Gamepad")).is_equal("xbox")
	assert_str(GlyphDB.detect_type("PS5 Controller")).is_equal("playstation")
	assert_str(GlyphDB.detect_type("Sony DualSense")).is_equal("playstation")
	assert_str(GlyphDB.detect_type("DualShock 4")).is_equal("playstation")
	assert_str(GlyphDB.detect_type("Nintendo Switch Pro Controller")).is_equal("switch")
	assert_str(GlyphDB.detect_type("Joy-Con (L/R)")).is_equal("switch")
	assert_str(GlyphDB.detect_type("Some Unknown Pad")).is_equal("generic")
	assert_str(GlyphDB.detect_type("")).is_equal("generic")


func test_detect_type_steam_input() -> void:
	# Steam masks the joy name; the vendor id recovers the real hardware.
	assert_str(GlyphDB.detect_type("Steam Virtual Gamepad", {"vendor_id": 0x054C})) \
		.is_equal("playstation")
	assert_str(GlyphDB.detect_type("Steam Virtual Gamepad", {"vendor_id": 0x057E})) \
		.is_equal("switch")
	assert_str(GlyphDB.detect_type("Steam Virtual Gamepad", {"vendor_id": 0x045E})) \
		.is_equal("xbox")
	# Unknown/absent vendor: Steam emulates XInput, so xbox prompts match
	# what the emulation layer presents — never accidentally generic.
	assert_str(GlyphDB.detect_type("Steam Virtual Gamepad")).is_equal("xbox")
	assert_str(GlyphDB.detect_type("Steam Controller", {"vendor_id": 0})).is_equal("xbox")
	# Steam Deck gets the generic set (which IS the Kenney Steam Deck art),
	# regardless of any vendor id it reports.
	assert_str(GlyphDB.detect_type("Steam Deck Controller", {"vendor_id": 0x054C})) \
		.is_equal("generic")


func test_default_map_targets_are_capturable_physicals() -> void:
	var map := GlyphDB.default_map()
	assert_bool(map.is_empty()).is_false()
	for logical: StringName in map:
		assert_bool(GlyphDB.FILE_FOR_PHYSICAL.has(map[logical])) \
			.override_failure_message("Default for %s is unglyphable: %s" % [logical, map[logical]]) \
			.is_true()
		assert_bool(GlyphDB.REBIND_CAPTURABLE.has(map[logical])) \
			.override_failure_message("Default for %s is not capturable: %s" % [logical, map[logical]]) \
			.is_true()


func test_default_map_has_no_duplicate_bindings() -> void:
	var map := GlyphDB.default_map()
	var seen := {}
	for logical: StringName in map:
		assert_bool(seen.has(map[logical])) \
			.override_failure_message("Physical %s bound twice" % map[logical]) \
			.is_false()
		seen[map[logical]] = true


func test_default_map_actions_exist_in_input_map() -> void:
	for logical: StringName in GlyphDB.default_map():
		assert_bool(InputMap.has_action(logical)) \
			.override_failure_message("Logical action missing from project.godot: %s" % logical) \
			.is_true()
	for physical: StringName in GlyphDB.FILE_FOR_PHYSICAL:
		if physical == &"controller_lstick":
			continue  # glyph-only alias, not an action
		assert_bool(InputMap.has_action(physical)) \
			.override_failure_message("Physical action missing from project.godot: %s" % physical) \
			.is_true()
