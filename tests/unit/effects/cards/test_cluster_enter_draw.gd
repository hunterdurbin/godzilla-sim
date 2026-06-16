extends GdUnitTestSuite

## Tier B cluster: cards whose <Enter> effect draws N cards (optionally
## discarding M afterwards), driven through the real trigger-dispatch seam
## (effect_handler.trigger_enter → registry → trigger_map → effect script).
## See classification.md for cluster membership.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")

const DECK_SIZE := 5
const HAND_SIZE := 3


## Place a real card on a board with a known hand/deck and return the wired
## session. Battle cards go to zone_idx; strategy cards to strategy zone 0.
func _setup(card_id: String, zone_idx: int) -> Dictionary:
	var card := Real.instance(card_id)
	var hand: Array[Dictionary] = []
	for i in range(HAND_SIZE):
		hand.append(Cards.battle(2, 3000, "HAND-%d" % i))
	var deck: Array[Dictionary] = []
	for i in range(DECK_SIZE):
		deck.append(Cards.battle(1, 2000, "DECK-%d" % i))
	var state := States.make_state({"p0": {"hand": hand, "main_deck": deck}})
	if int(card.get("card_type", -1)) == CardEnums.CardType.STRATEGY:
		state.players[0].strategy_zones[0] = card
	else:
		state.players[0].push_zone_card(zone_idx, card)
	var session := States.make_session(state)
	session["state"] = state
	session["card"] = card
	return session


func test_enter_draws_then_discards(card_id: String, zone_idx: int, draw_count: int, discard_count: int,
		test_parameters := [
			["EBP01-032", 2, 2, 0],
			["EBP01-047", 2, 1, 1],
			["EBP01-055", 2, 1, 1],
			["EBP03-049", 7, 2, 2],
		]) -> void:
	var s := _setup(card_id, zone_idx)
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].trigger_enter(0, s["card"])

	assert_int(state.players[0].hand.size()) \
		.override_failure_message("%s: hand size after draw %d / discard %d" % [card_id, draw_count, discard_count]) \
		.is_equal(HAND_SIZE + draw_count - discard_count)
	assert_int(state.players[0].main_deck.size()).is_equal(DECK_SIZE - draw_count)
	assert_int(state.players[0].discard_pile.size()).is_equal(discard_count)
	# The discard half must actually prompt the player (default answer applies).
	assert_int(input.count_calls("choose_hand_discards")).is_equal(1 if discard_count > 0 else 0)


func test_enter_does_nothing_outside_required_zone(card_id: String, wrong_zone: int,
		test_parameters := [
			["EBP03-049", 2],  # requires zone 8 (idx 7)
		]) -> void:
	var s := _setup(card_id, wrong_zone)
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, s["card"])

	assert_int(state.players[0].hand.size()).is_equal(HAND_SIZE)
	assert_int(state.players[0].main_deck.size()).is_equal(DECK_SIZE)
	assert_int(state.players[0].discard_pile.size()).is_equal(0)
