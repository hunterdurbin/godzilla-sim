extends GdUnitTestSuite

## Deck-building over-limit workflow: adding past 50 main-deck cards / 10
## Step-2 cards is allowed (over-fill then shave down), the per-card copy
## cap still applies, and over-limit decks save normally — legality is
## flagged at deck-select time, not at save time.

const SAVE_NAME := "__gdunit_over_limit_deck__"

var _builder: Control


func before_test() -> void:
	_builder = auto_free(load("res://scenes/deck_builder/DeckBuilder.tscn").instantiate())
	add_child(_builder)
	_builder._game_mode = "rumble_west"


func after_test() -> void:
	DecklistManager.delete_decklist(SAVE_NAME)


func test_main_deck_can_exceed_50() -> void:
	_builder._main_entries = [
		{"card_number": "ESD01-008", "quantity": 46},
		{"card_number": "ESD01-009", "quantity": 4},
	]
	_builder._add_to_main_deck("ESD01-010")
	assert_int(_builder._get_main_deck_total()).is_equal(51)


func test_step2_can_exceed_10() -> void:
	_builder._main_entries = [{"card_number": "ESD01-004", "quantity": 10}]
	_builder._add_to_main_deck("ESD01-012")
	assert_int(_builder._get_step2_count()).is_equal(11)


func test_copy_cap_still_enforced() -> void:
	_builder._main_entries = [{"card_number": "ESD01-010", "quantity": 4}]
	_builder._add_to_main_deck("ESD01-010")
	assert_int(_builder._get_main_deck_total()).is_equal(4)


func test_copy_cap_enforced_in_unrestricted() -> void:
	_builder._game_mode = "unrestricted"
	_builder._main_entries = [{"card_number": "ESD01-010", "quantity": 4}]
	_builder._add_to_main_deck("ESD01-010")
	assert_int(_builder._get_main_deck_total()).is_equal(4)


func test_over_limit_deck_saves_normally() -> void:
	_builder._main_entries = [
		{"card_number": "ESD01-008", "quantity": 46},
		{"card_number": "ESD01-009", "quantity": 4},
		{"card_number": "ESD01-010", "quantity": 1},
	]
	_builder.deck_name_edit.text = SAVE_NAME
	_builder._on_save_pressed()
	assert_bool(SAVE_NAME in DecklistManager.get_all_decklists()).is_true()
	assert_bool(DecklistManager.validate_decklist(SAVE_NAME).is_empty()).is_false()
