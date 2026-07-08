extends GdUnitTestSuite

## DeckBuilderPadHints — controller hint rows per focus context and the LB/RB
## section cycle of the deck builder screen.


func _keys(hints: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for h in hints:
		out.append(String(h["text_key"]))
	return out


func test_pool_card_hints() -> void:
	var hints := DeckBuilderPadHints.compute({"area": "pool"})
	assert_array(_keys(hints)).is_equal(["STR_DB_HINT_ADD", "STR_DB_HINT_REMOVE",
			"STR_DB_HINT_SECTION", "STR_DB_HINT_BACK"] as Array[String])
	assert_str(String(hints[0]["action"])).is_equal("pad_confirm")
	assert_str(String(hints[1]["action"])).is_equal("pad_end_main")
	# The section hint shows the LB/RB pair.
	assert_str(String(hints[2]["action"])).is_equal("pad_focus_log")
	assert_str(String(hints[2]["action2"])).is_equal("pad_focus_tracker")


func test_deck_card_hints_monster_tab() -> void:
	var hints := DeckBuilderPadHints.compute({"area": "deck", "monster_tab": true})
	assert_str(_keys(hints)[0]).is_equal("STR_DB_HINT_REMOVE")
	assert_str(_keys(hints)[1]).is_equal("STR_DB_HINT_TO_MAIN")


func test_deck_card_hints_main_tab_monster_type() -> void:
	var hints := DeckBuilderPadHints.compute(
			{"area": "deck", "monster_tab": false, "is_monster_type": true})
	assert_str(_keys(hints)[1]).is_equal("STR_DB_HINT_TO_MONSTER")


func test_deck_card_hints_main_tab_monster_already_in_monster_deck() -> void:
	# The hover move button reads "To Main" here (pulls the monster-deck copy
	# into main) — X mirrors it.
	var hints := DeckBuilderPadHints.compute({"area": "deck", "monster_tab": false,
			"is_monster_type": true, "in_monster": true})
	assert_str(_keys(hints)[1]).is_equal("STR_DB_HINT_TO_MAIN")


func test_deck_card_hints_main_tab_regular() -> void:
	var hints := DeckBuilderPadHints.compute({"area": "deck", "monster_tab": false})
	assert_str(_keys(hints)[1]).is_equal("STR_DB_HINT_REMOVE_ALL")


func test_chrome_hints() -> void:
	var hints := DeckBuilderPadHints.compute({})
	assert_array(_keys(hints)).is_equal(["STR_GB_HINT_SELECT",
			"STR_DB_HINT_SECTION", "STR_DB_HINT_BACK"] as Array[String])


func test_next_section_cycles_and_wraps() -> void:
	assert_str(DeckBuilderPadHints.next_section("left", 1)).is_equal("deck")
	assert_str(DeckBuilderPadHints.next_section("deck", 1)).is_equal("pool")
	assert_str(DeckBuilderPadHints.next_section("pool", 1)).is_equal("left")
	assert_str(DeckBuilderPadHints.next_section("left", -1)).is_equal("pool")
	assert_str(DeckBuilderPadHints.next_section("deck", -1)).is_equal("left")
	# Unknown section clamps to the start of the cycle before stepping.
	assert_str(DeckBuilderPadHints.next_section("bogus", 1)).is_equal("deck")
