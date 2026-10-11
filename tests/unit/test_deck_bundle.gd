extends GdUnitTestSuite

## DecklistManager's all-decks clipboard bundle: format round trip, parsing
## edge cases, and the never-overwrite conflict rules. Pure static helpers
## only — nothing here touches user://decklists.

const DecklistManagerScript := preload("res://scripts/cards/decklist_manager.gd")


func _deck(deck_name: String, folder: String, monster: Array, main: Array) -> Dictionary:
	return {"name": deck_name, "folder": folder, "monster": monster, "main": main}


func _e(qty: int, card: String) -> Dictionary:
	return {"quantity": qty, "card_number": card}


func test_round_trip_keeps_names_folders_and_cards() -> void:
	var decks := [
		_deck("Godzilla Rush", "", [_e(1, "EBP01-001")], [_e(4, "EBP01-010"), _e(2, "EBP02-033")]),
		_deck("Shin v3", "Iterations/Shin", [_e(1, "EBP03-002")], [_e(3, "EBP03-050")]),
	]
	var parsed := DecklistManagerScript.parse_deck_bundle(DecklistManagerScript.build_deck_bundle(decks))
	assert_int(parsed.size()).is_equal(2)
	assert_str(parsed[0]["name"]).is_equal("Godzilla Rush")
	assert_str(parsed[0]["folder"]).is_empty()
	assert_str(parsed[1]["name"]).is_equal("Shin v3")
	assert_str(parsed[1]["folder"]).is_equal("Iterations/Shin")
	assert_bool(DecklistManagerScript.same_deck_contents(parsed[0], decks[0])).is_true()
	assert_bool(DecklistManagerScript.same_deck_contents(parsed[1], decks[1])).is_true()


func test_single_deck_paste_is_not_a_bundle() -> void:
	var single := "[monster deck]\n1 EBP01-001\n\n[main deck]\n4 EBP01-010\n"
	assert_array(DecklistManagerScript.parse_deck_bundle(single)).is_empty()


func test_parse_tolerates_crlf_case_and_empty_blocks() -> void:
	var text := "# header\r\n[DECK] Empty One\r\n[monster deck]\r\n[main deck]\r\n" \
		+ "[Deck] Real\r\n[Monster Deck]\r\n1 ebp01-001\r\n[Main Deck]\r\n4 EBP01-010\r\n"
	var parsed := DecklistManagerScript.parse_deck_bundle(text)
	assert_int(parsed.size()).is_equal(1)
	assert_str(parsed[0]["name"]).is_equal("Real")
	assert_str(parsed[0]["monster"][0]["card_number"]).is_equal("EBP01-001")


func test_header_path_is_sanitized() -> void:
	var text := "[deck] Bad: Folder / What?\n[monster deck]\n1 EBP01-001\n[main deck]\n4 EBP01-010\n"
	var parsed := DecklistManagerScript.parse_deck_bundle(text)
	assert_str(parsed[0]["folder"]).is_equal("Bad- Folder")
	assert_str(parsed[0]["name"]).is_equal("What_")


func test_same_deck_contents_ignores_order_and_split_lines() -> void:
	var a := {"monster": [_e(1, "EBP01-001")], "main": [_e(2, "EBP01-010"), _e(2, "EBP01-010"), _e(1, "EBP02-001")]}
	var b := {"monster": [_e(1, "ebp01-001")], "main": [_e(1, "EBP02-001"), _e(4, "EBP01-010")]}
	assert_bool(DecklistManagerScript.same_deck_contents(a, b)).is_true()
	b["main"][1]["quantity"] = 3
	assert_bool(DecklistManagerScript.same_deck_contents(a, b)).is_false()


func test_unique_import_name_never_collides() -> void:
	var taken := {"Foo": true, "Foo (imported)": true, "Foo (imported 2)": true}
	assert_str(DecklistManagerScript.unique_import_name("Foo", taken)).is_equal("Foo (imported 3)")
	assert_str(DecklistManagerScript.unique_import_name("Bar", taken)).is_equal("Bar (imported)")


func test_summarize_import_plan_counts_actions() -> void:
	var plan: Array[Dictionary] = [
		{"action": "new"}, {"action": "skipped"}, {"action": "renamed"}, {"action": "new"},
	]
	assert_dict(DecklistManagerScript.summarize_import_plan(plan)).is_equal({"new": 2, "renamed": 1, "skipped": 1})
