extends GdUnitTestSuite

## GameModeValidator "unrestricted" (formerly "no_rules"): every implemented
## card is legal (spoiled sets land here before any Rumble pool) and no
## ban/restricted lists apply, but standard deck-building rules still do.


func test_legacy_no_rules_id_maps_to_unrestricted() -> void:
	assert_str(GameModeValidator.normalize_mode_id("no_rules")).is_equal("unrestricted")
	assert_str(GameModeValidator.get_mode("no_rules").get("id", "")).is_equal("unrestricted")


func test_spoiled_sets_are_unrestricted_only() -> void:
	for card in ["ESD03-005", "ESD04-004", "ESD05-002"]:
		assert_bool(GameModeValidator.is_card_valid_for_mode(card, "unrestricted")).is_true()
		assert_bool(GameModeValidator.is_card_valid_for_mode(card, "rumble_west")).is_false()
		assert_bool(GameModeValidator.is_card_valid_for_mode(card, "rumble_east")).is_false()
		assert_bool(GameModeValidator.is_card_valid_for_mode(card, "bulkzilla")).is_false()


func test_banned_cards_are_legal_in_unrestricted() -> void:
	# restricted_0 in every Rumble format; no lists in unrestricted.
	var entries := [{"card_number": "EBP01-079", "quantity": 1}]
	assert_dict(GameModeValidator.get_invalid_cards("unrestricted", [], entries)).is_empty()
	assert_dict(GameModeValidator.get_invalid_cards("rumble_west", [], entries)).contains_keys(["EBP01-079"])


func test_unrestricted_enforces_copy_limit_and_deck_rules() -> void:
	var entries := [{"card_number": "EBP01-018", "quantity": 5}]
	assert_dict(GameModeValidator.get_invalid_cards("unrestricted", [], entries)).contains_keys(["EBP01-018"])
	# Not a legal deck either (no monsters, 5-card main deck).
	assert_array(GameModeValidator.validate("unrestricted", [], entries)).is_not_empty()


func test_spoiled_sets_lists_sets_outside_every_rumble_pool() -> void:
	var ids := ["EBP01-001", "ESD02-004", "ESD03-005", "ESD03-007", "ESD05-002", "RAGE-001"]
	assert_array(GameModeValidator.get_spoiled_sets(ids)).contains_exactly(["ESD03", "ESD05"])
