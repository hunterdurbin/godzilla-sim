extends GdUnitTestSuite

## CardSearch: the deck-builder search grammar as a reusable static utility
## (comma-separated AND criteria, `!` negation, numeric compares like
## cp>2000 / r=3 / bare >1000, fuzzy substring over name/id/description/
## traits/common_names).

const Cards := preload("res://tests/fixtures/cards.gd")


func _weak(id: String = "WEAK") -> Dictionary:
	return Cards.battle(1, 1000, id)


func _strong(id: String = "STRONG") -> Dictionary:
	return Cards.battle(3, 8000, id)


func test_empty_query_matches_everything() -> void:
	var criteria: Array = CardSearch.parse("")
	assert_bool(CardSearch.matches(_weak(), criteria)).is_true()


func test_fuzzy_matches_name_and_id() -> void:
	var criteria: Array = CardSearch.parse("strong")
	assert_bool(CardSearch.matches(_strong(), criteria)).is_true()
	assert_bool(CardSearch.matches(_weak(), criteria)).is_false()


func test_compare_filters_counter_power() -> void:
	var criteria: Array = CardSearch.parse("cp>2000")
	assert_bool(CardSearch.matches(_strong(), criteria)).is_true()
	assert_bool(CardSearch.matches(_weak(), criteria)).is_false()


func test_bare_compare_checks_any_numeric_field() -> void:
	var criteria: Array = CardSearch.parse(">7000")
	assert_bool(CardSearch.matches(_strong(), criteria)).is_true()
	assert_bool(CardSearch.matches(_weak(), criteria)).is_false()


func test_rank_alias_and_equals() -> void:
	var criteria: Array = CardSearch.parse("r=3")
	assert_bool(CardSearch.matches(_strong(), criteria)).is_true()
	assert_bool(CardSearch.matches(_weak(), criteria)).is_false()


func test_comma_criteria_are_anded() -> void:
	var criteria: Array = CardSearch.parse("strong, cp>2000")
	assert_bool(CardSearch.matches(_strong(), criteria)).is_true()
	var strong_but_wrong_name := Cards.battle(3, 8000, "OTHER")
	assert_bool(CardSearch.matches(strong_but_wrong_name, criteria)).is_false()


func test_negation_excludes_matches() -> void:
	var criteria: Array = CardSearch.parse("!strong")
	assert_bool(CardSearch.matches(_strong(), criteria)).is_false()
	assert_bool(CardSearch.matches(_weak(), criteria)).is_true()


func test_trait_fuzzy_match() -> void:
	var mon := Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "MON")
	var criteria: Array = CardSearch.parse(CardEnums.trait_to_string(CardEnums.CardTrait.GODZILLA).to_lower())
	assert_bool(CardSearch.matches(mon, criteria)).is_true()
