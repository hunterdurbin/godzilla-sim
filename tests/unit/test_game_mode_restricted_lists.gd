extends GdUnitTestSuite

## GameModeValidator restricted lists: `restricted_0` bans a card outright
## (0 copies), `restricted_1` caps it at a single copy across monster + main.


func _errors(mode: String, main_entries: Array) -> Array[String]:
	var m := GameModeValidator.get_mode(mode)
	return GameModeValidator._validate_pool_restrictions(m, [], main_entries)


func _invalid(mode: String, main_entries: Array) -> Dictionary:
	var m := GameModeValidator.get_mode(mode)
	var invalid: Dictionary = {}
	GameModeValidator._flag_pool_invalid(m["card_pool"], mode, [], main_entries, invalid)
	return invalid


func test_restricted_0_cards_listed_in_all_three_formats() -> void:
	for mode in ["rumble_west", "rumble_east", "bulkzilla"]:
		var pool: Dictionary = GameModeValidator.get_mode(mode)["card_pool"]
		assert_array(pool["restricted_0"]).contains(["EBP01-079", "EBP03-016"])
		assert_array(pool["restricted_1"]).not_contains(["EBP01-079", "EBP03-016"])


func test_restricted_0_single_copy_is_an_error() -> void:
	var entries := [{"card_number": "EBP01-079", "quantity": 1}]
	assert_array(_errors("rumble_west", entries)).has_size(1)
	assert_dict(_invalid("rumble_west", entries)).contains_keys(["EBP01-079"])


func test_restricted_1_single_copy_is_fine() -> void:
	var entries := [{"card_number": "EBP01-077", "quantity": 1}]
	assert_array(_errors("rumble_west", entries)).is_empty()
	assert_dict(_invalid("rumble_west", entries)).is_empty()


func test_restricted_1_two_copies_is_an_error() -> void:
	var entries := [{"card_number": "EBP01-077", "quantity": 2}]
	assert_array(_errors("rumble_east", entries)).has_size(1)
	assert_dict(_invalid("rumble_east", entries)).contains_keys(["EBP01-077"])


func test_bulkzilla_bans_restricted_0_cards() -> void:
	var entries := [{"card_number": "EBP03-016", "quantity": 1}]
	assert_array(_errors("bulkzilla", entries)).has_size(1)
