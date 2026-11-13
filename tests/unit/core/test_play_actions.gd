extends GdUnitTestSuite

## PlayActions: overload is performed when a card is placed
## (docs/adr/0001-overload-at-placement.md), not at the check timing.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func test_overload_discards_and_counts_card_as_destroyed() -> void:
	# Rule 11.5.1: playing into an occupied zone destroys the existing card —
	# it goes to the discard AND counts as destroyed this turn (no revenge).
	var covered := Cards.battle(1, 5000, "COVERED")
	var state := States.make_state({"p0": {
		"hand": [Cards.battle(2, 5000, "INCOMING")],
		"zone_cards": {4: covered},
	}})
	var session := States.make_session(state)

	await session["action_handler"].execute(
		CardEnums.ActionType.PLAY_BATTLE, {"hand_index": 0, "zone_index": 4}, state)

	var p0 := state.players[0]
	assert_str(str(p0.get_zone_top_card(4).get("id"))).is_equal("INCOMING")
	assert_int(p0.discard_pile.size()).is_equal(1)
	assert_str(str(p0.discard_pile[0].get("id"))).is_equal("COVERED")
	assert_int(p0.cards_destroyed_this_turn.size()).is_equal(1)
	assert_str(str(p0.cards_destroyed_this_turn[0].get("id"))).is_equal("COVERED")
