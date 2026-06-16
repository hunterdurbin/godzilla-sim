extends GdUnitTestSuite

## Tier B cluster: cards whose trigger mills (own deck top → own discard via
## ctx.mill/mill_one) with at most a simple conditional follow-up keyed off
## the milled card's type, driven through the real trigger-dispatch seam
## (effect_handler.trigger_* → registry → trigger_map → effect script).
## See classification.md for cluster membership.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")

## Filler cards stacked UNDER the controlled top card in each deck.
const FILLER := 3


## The controlled deck-top card for a branch. PlayerState.mill_cards pops
## main_deck.pop_front(), so index 0 is the deck top.
static func _top_card(kind: String) -> Dictionary:
	match kind:
		"monster":
			return Cards.monster(2, 9000, [CardEnums.CardTrait.GODZILLA], "TOP-MONSTER")
		"green_battle":
			var card := Cards.battle(2, 3000, "TOP-GREEN")
			card["colors"] = [CardEnums.CardColor.GREEN]
			return card
		_:
			return Cards.battle(2, 3000, "TOP-BATTLE")


static func _top_id(kind: String) -> String:
	match kind:
		"monster":
			return "TOP-MONSTER"
		"green_battle":
			return "TOP-GREEN"
		_:
			return "TOP-BATTLE"


static func _stacked_deck(top_kind: String) -> Array[Dictionary]:
	var deck: Array[Dictionary] = [_top_card(top_kind)]
	for i in range(FILLER):
		deck.append(Cards.battle(1, 2000, "FILLER-%d" % i))
	return deck


static func _ids(cards: Array) -> Array[String]:
	var out: Array[String] = []
	for c in cards:
		out.append(str(c.get("id", "")))
	return out


static func _calls_of(input: ScriptedPlayerInput, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in input.calls:
		if c["kind"] == kind:
			out.append(c)
	return out


## EBP01-002 <When Invading>: mill 1; if it is a monster card, <Destroy> 1
## opponent rank<=5 battle card.
func test_ebp01_002_invading_mill_destroys_low_rank_on_monster(top_kind: String, expect_destroy: bool,
		test_parameters := [
			["monster", true],
			["battle", false],
		]) -> void:
	var card := Real.instance("EBP01-002")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 2, "main_deck": _stacked_deck(top_kind)},
		"p1": {"zone_cards": {3: Cards.battle(2, 3000, "OPP-R2"), 5: Cards.battle(6, 6000, "OPP-R6")}},
	})
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"select_zone": [3]}

	await s["effect_handler"].trigger_when_invading(0, 1, 2)

	assert_int(state.players[0].main_deck.size()).is_equal(FILLER)
	assert_array(_ids(state.players[0].discard_pile)) \
		.override_failure_message("EBP01-002 (%s top): exactly the milled top card in own discard" % top_kind) \
		.contains_exactly([_top_id(top_kind)])
	if expect_destroy:
		assert_bool(state.players[1].zone_has_cards(3)).is_false()
		assert_bool(state.players[1].zone_has_cards(5)).is_true()  # rank 6 not a valid target
		assert_array(_ids(state.players[1].discard_pile)).contains_exactly(["OPP-R2"])
		assert_array(_calls_of(input, "select_zone")[0]["valid"]).contains_exactly([3])
	else:
		assert_bool(state.players[1].zone_has_cards(3)).is_true()
		assert_int(state.players[1].discard_pile.size()).is_equal(0)
		assert_int(input.count_calls("select_zone")).is_equal(0)


## EBP01-072 <Enter>: only in the opponent monster's column, mill 1; if it is
## a battle card, retreat the opponent's monster (TL<=50000) by 1 zone.
func test_ebp01_072_enter_column_mill_retreats_weak_monster(zone_idx: int, top_kind: String, opp_threat: int, expect_mill: bool, expected_opp_zone: int,
		test_parameters := [
			[2, "battle", 40000, true, 2],   # same column, battle top, TL low → retreat
			[2, "monster", 40000, true, 3],  # monster top → mill only
			[0, "battle", 40000, false, 3],  # wrong column → no mill at all
			[2, "battle", 60000, true, 3],   # TL above 50k → mill only
		]) -> void:
	var card := Real.instance("EBP01-072")
	var state := States.make_state({
		"p0": {"zone_cards": {zone_idx: card}, "main_deck": _stacked_deck(top_kind)},
		"p1": {"monster_zone": 3, "current_monster": Cards.monster(3, opp_threat)},
	})
	var s := States.make_session(state)

	await s["effect_handler"].trigger_enter(0, card)

	var expected_deck: int = FILLER if expect_mill else FILLER + 1
	assert_int(state.players[0].main_deck.size()) \
		.override_failure_message("EBP01-072 (zone %d, %s top): deck after enter" % [zone_idx, top_kind]) \
		.is_equal(expected_deck)
	assert_int(state.players[0].discard_pile.size()).is_equal(1 if expect_mill else 0)
	if expect_mill:
		assert_array(_ids(state.players[0].discard_pile)).contains_exactly([_top_id(top_kind)])
	assert_int(state.players[1].monster_zone) \
		.override_failure_message("EBP01-072 (TL %d, %s top): opponent monster zone" % [opp_threat, top_kind]) \
		.is_equal(expected_opp_zone)


## EBP02-014 <Enter>: mill 1; if it is a monster card, advance own monster to zone 6.
func test_ebp02_014_enter_mill_advances_monster(top_kind: String, expected_zone: int,
		test_parameters := [
			["monster", 6],
			["battle", 1],
		]) -> void:
	var card := Real.instance("EBP02-014")
	var state := States.make_state({
		"p0": {"zone_cards": {7: card}, "main_deck": _stacked_deck(top_kind)},
	})
	var s := States.make_session(state)

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].main_deck.size()).is_equal(FILLER)
	assert_array(_ids(state.players[0].discard_pile)).contains_exactly([_top_id(top_kind)])
	assert_int(state.players[0].monster_zone) \
		.override_failure_message("EBP02-014 (%s top): monster zone after enter" % top_kind) \
		.is_equal(expected_zone)


## EBP02-047: whenever this (monster) card advances, mill 1 — no follow-up.
func test_ebp02_047_advance_mills_one(top_kind: String,
		test_parameters := [
			["battle"],
			["monster"],
		]) -> void:
	var card := Real.instance("EBP02-047")
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 2, "main_deck": _stacked_deck(top_kind)},
	})
	var s := States.make_session(state)

	await s["effect_handler"].trigger_monster_advance(0, 1, 2)

	assert_int(state.players[0].main_deck.size()).is_equal(FILLER)
	assert_array(_ids(state.players[0].discard_pile)).contains_exactly([_top_id(top_kind)])


## EBP03-031 <Enter>: look at the deck top; optionally mill it or put it back.
func test_ebp03_031_enter_optional_mill(take_mill: bool,
		test_parameters := [
			[true],
			[false],
		]) -> void:
	var card := Real.instance("EBP03-031")
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "main_deck": _stacked_deck("battle")},
	})
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	# select_from_cards routes through input.search_cards: pick the shown top
	# card to mill it, or {} to put it back.
	input.answers = {"search_cards": [{"id": "TOP-BATTLE"} if take_mill else {}]}

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(input.count_calls("search_cards")).is_equal(1)
	assert_array(_ids(_calls_of(input, "search_cards")[0]["matching"])).contains_exactly(["TOP-BATTLE"])
	if take_mill:
		assert_int(state.players[0].main_deck.size()).is_equal(FILLER)
		assert_array(_ids(state.players[0].discard_pile)).contains_exactly(["TOP-BATTLE"])
	else:
		assert_int(state.players[0].main_deck.size()).is_equal(FILLER + 1)
		# select_from_cards never touches the deck, so the top card stays put.
		assert_str(str(state.players[0].main_deck[0].get("id"))).is_equal("TOP-BATTLE")
		assert_int(state.players[0].discard_pile.size()).is_equal(0)


## EBP04-021: at the beginning of YOUR counter phase, mill 1; if it is a
## green battle card, the opponent discards down to 4 cards in hand.
func test_ebp04_021_counter_start_mill_forces_opp_discard_to_4(top_kind: String, expected_opp_hand: int,
		test_parameters := [
			["green_battle", 4],
			["battle", 6],
			["monster", 6],
		]) -> void:
	var card := Real.instance("EBP04-021")
	var opp_hand: Array[Dictionary] = []
	for i in range(6):
		opp_hand.append(Cards.battle(1, 2000, "OPPH-%d" % i))
	var state := States.make_state({
		"p0": {"current_monster": card, "main_deck": _stacked_deck(top_kind)},
		"p1": {"hand": opp_hand},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"choose_hand_discards": [[4, 5]]}

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].main_deck.size()).is_equal(FILLER)
	assert_array(_ids(state.players[0].discard_pile)).contains_exactly([_top_id(top_kind)])
	assert_int(state.players[1].hand.size()) \
		.override_failure_message("EBP04-021 (%s top): opponent hand size" % top_kind) \
		.is_equal(expected_opp_hand)
	assert_int(state.players[1].discard_pile.size()).is_equal(6 - expected_opp_hand)
	assert_int(input.count_calls("choose_hand_discards")).is_equal(1 if expected_opp_hand == 4 else 0)


## EBP04-021 TRIGGER_FILTERS gate: own_turn=true — silent on the opponent's
## counter phase.
func test_ebp04_021_does_not_fire_on_opponent_turn() -> void:
	var card := Real.instance("EBP04-021")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": card, "main_deck": _stacked_deck("green_battle")},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := States.make_session(state)

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].main_deck.size()).is_equal(FILLER + 1)
	assert_int(state.players[0].discard_pile.size()).is_equal(0)


## EBP04-075 (strategy) <Opponent's Turn>: at the beginning of the counter
## phase, mill 1; if it is a monster card, <Destroy> 1 opponent battle card
## in the own monster's column.
func test_ebp04_075_opp_counter_start_mill_destroys_column(top_kind: String, expect_destroy: bool,
		test_parameters := [
			["monster", true],
			["battle", false],
		]) -> void:
	var card := Real.instance("EBP04-075")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"strategy_zones": [card], "monster_zone": 1, "main_deck": _stacked_deck(top_kind)},
		"p1": {"zone_cards": {4: Cards.battle(2, 3000, "OPP-COL"), 2: Cards.battle(2, 3000, "OPP-OFF")}},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"select_zone": [4]}

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].main_deck.size()).is_equal(FILLER)
	assert_array(_ids(state.players[0].discard_pile)).contains_exactly([_top_id(top_kind)])
	if expect_destroy:
		# Own monster on zone 1 → opponent column zones are idx 4/5; only idx 4 holds a card.
		assert_array(_calls_of(input, "select_zone")[0]["valid"]).contains_exactly([4])
		assert_bool(state.players[1].zone_has_cards(4)).is_false()
		assert_bool(state.players[1].zone_has_cards(2)).is_true()
		assert_array(_ids(state.players[1].discard_pile)).contains_exactly(["OPP-COL"])
	else:
		assert_int(input.count_calls("select_zone")).is_equal(0)
		assert_bool(state.players[1].zone_has_cards(4)).is_true()
		assert_int(state.players[1].discard_pile.size()).is_equal(0)
