extends GdUnitTestSuite

## MaxCounterDialog's per-deck default detection: decks whose monster deck
## runs EBP03-013 (grows strategy zones to 3 for the rest of the game) open
## the Max Counter Power preview with the 3-zone assumption pre-selected.


func test_deck_with_ebp03_013_expands_strategy_zones() -> void:
	var monster_entries := [
		{"card_number": "EBP02-052", "quantity": 1},
		{"card_number": "EBP03-013", "quantity": 1},
	]
	assert_bool(MaxCounterDialog.deck_expands_strategy_zones(monster_entries)).is_true()


func test_deck_without_ebp03_013_keeps_two_zones() -> void:
	var monster_entries := [{"card_number": "EBP02-052", "quantity": 1}]
	assert_bool(MaxCounterDialog.deck_expands_strategy_zones(monster_entries)).is_false()
	assert_bool(MaxCounterDialog.deck_expands_strategy_zones([])).is_false()
