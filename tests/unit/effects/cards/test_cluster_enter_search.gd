extends GdUnitTestSuite

## Tier B cluster: cards whose trigger searches a card source (deck / discard
## / deck-top reveal) with a filter and moves the pick somewhere (hand / play
## / discard / deck top), driven through the real trigger-dispatch seam
## (effect_handler.trigger_* → registry → trigger_map → effect script).
## Each test seeds both matching and non-matching cards and asserts the
## offered "matching" pool only held filter matches.
## See classification.md for cluster membership.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


static func _green_battle(id: String) -> Dictionary:
	var card := Cards.battle(2, 3000, id)
	card["colors"] = [CardEnums.CardColor.GREEN]
	return card


static func _blue_battle(id: String) -> Dictionary:
	var card := Cards.battle(2, 3000, id)
	card["colors"] = [CardEnums.CardColor.BLUE]
	return card


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


## EBP01-019 <Awakening6> <Enter> (from hand): search the deck for up to 2
## Kamacuras battle cards and play them.
func test_ebp01_019_enter_plays_kamacuras_from_deck_when_awakened(monster_zone: int, expect_search: bool,
		test_parameters := [
			[6, true],
			[5, false],
		]) -> void:
	var card := Real.instance("EBP01-019")
	var kama1 := Real.instance("EBP01-019", 1)
	var kama2 := Real.instance("EBP01-019", 2)
	var deck: Array[Dictionary] = [
		kama1,
		Cards.battle(2, 3000, "DECK-BTL"),  # battle without the trait
		kama2,
		Cards.monster(1, 5000, [CardEnums.CardTrait.KAMACURAS], "DECK-KAMA-MON"),  # trait but not battle
	]
	var state := States.make_state({
		"p0": {"monster_zone": monster_zone, "zone_cards": {7: card}, "main_deck": deck},
	})
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {
		"search_cards": [{"id": kama1["id"]}, {"id": kama2["id"]}],
		"select_zone": [0, 1],
	}

	await s["effect_handler"].trigger_enter(0, card)

	if expect_search:
		assert_str(str(state.players[0].get_zone_top_card(0).get("id"))).is_equal(str(kama1["id"]))
		assert_str(str(state.players[0].get_zone_top_card(1).get("id"))).is_equal(str(kama2["id"]))
		assert_int(state.players[0].main_deck.size()).is_equal(2)
		var searches := _calls_of(input, "search_cards")
		assert_int(searches.size()).is_equal(2)
		assert_array(_ids(searches[0]["matching"])) \
			.override_failure_message("EBP01-019: first search pool must be Kamacuras battle cards only") \
			.contains_exactly_in_any_order([kama1["id"], kama2["id"]])
		assert_array(_ids(searches[1]["matching"])).contains_exactly([kama2["id"]])
	else:
		assert_int(input.count_calls("search_cards")).is_equal(0)
		assert_int(state.players[0].main_deck.size()).is_equal(4)


## EBP01-034 <Enter> (monster): play 1 rank<=4 battle card with <Evolution>
## from the discard pile into a zone adjacent to this card.
func test_ebp01_034_enter_plays_evolution_battle_from_discard() -> void:
	var card := Real.instance("EBP01-034")
	var wanted := Real.instance("EBP01-044")    # rank 1 battle, Evolution5
	var too_high := Real.instance("EBP01-054")  # Evolution battle but rank 6
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 1}})
	state.players[0].discard_pile.append_array([
		wanted, too_high,
		Cards.battle(2, 3000, "DIS-BTL"),  # rank ok, no evolution_rank
		Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "DIS-MON"),
	])
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"search_cards": [{"id": wanted["id"]}], "select_zone": [1]}

	await s["effect_handler"].trigger_enter(0, card)

	assert_str(str(state.players[0].get_zone_top_card(1).get("id"))).is_equal(str(wanted["id"]))
	assert_int(state.players[0].discard_pile.size()).is_equal(3)
	assert_array(_ids(_calls_of(input, "search_cards")[0]["matching"])).contains_exactly([wanted["id"]])
	# Monster on zone 1 → the only adjacent play zone is idx 1.
	assert_array(_calls_of(input, "select_zone")[0]["valid"]).contains_exactly([1])


## EBP02-058 / EBP02-062 <Revenge>: return up to 1 trait-matching monster card
## from the discard pile to hand.
func test_revenge_returns_trait_monster_from_discard(card_id: String, wanted_id: String,
		test_parameters := [
			["EBP02-058", "EBP02-047"],  # King Ghidorah monster
			["EBP02-062", "EBP02-053"],  # SpaceGodzilla monster
		]) -> void:
	var card := Real.instance(card_id)
	var wanted := Real.instance(wanted_id)
	var state := States.make_state()
	state.players[0].discard_pile.append_array([
		card,  # revenge fires after the card itself was destroyed into discard
		wanted,
		Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "DIS-MON"),  # wrong trait
		Cards.battle(2, 3000, "DIS-BTL"),  # not a monster
	])
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"search_cards": [{"id": wanted["id"]}]}

	await s["effect_handler"].trigger_revenge(0, card)

	assert_array(_ids(state.players[0].hand)) \
		.override_failure_message("%s: %s should return to hand" % [card_id, wanted_id]) \
		.contains_exactly([wanted["id"]])
	assert_int(state.players[0].discard_pile.size()).is_equal(3)
	assert_array(_ids(_calls_of(input, "search_cards")[0]["matching"])).contains_exactly([wanted["id"]])


## EBP03-021 <Enter> (monster): return 1 strategy card with <Base> from the
## discard pile to hand.
func test_ebp03_021_enter_returns_base_strategy_from_discard() -> void:
	var card := Real.instance("EBP03-021")
	var wanted := Real.instance("EBP03-070")  # is_base strategy
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 1}})
	state.players[0].discard_pile.append_array([
		wanted,
		Cards.strategy(1, "DIS-STR"),      # strategy without Base
		Cards.battle(2, 3000, "DIS-BTL"),  # not a strategy
	])
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"search_cards": [{"id": wanted["id"]}]}

	await s["effect_handler"].trigger_enter(0, card)

	assert_array(_ids(state.players[0].hand)).contains_exactly([wanted["id"]])
	assert_int(state.players[0].discard_pile.size()).is_equal(2)
	assert_array(_ids(_calls_of(input, "search_cards")[0]["matching"])).contains_exactly([wanted["id"]])


## EBP03-007 <When Invading> (monster): reveal deck-top cards equal to the
## opponent monster's rank, add 1 red/blue battle card to hand, discard the rest.
func test_ebp03_007_invading_reveals_and_adds_red_or_blue_battle() -> void:
	var card := Real.instance("EBP03-007")
	var deck: Array[Dictionary] = [
		Cards.battle(2, 3000, "RV-RED"),
		Cards.strategy(1, "RV-STR"),  # blue but not a battle card
		Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "RV-MON"),
		Cards.battle(1, 2000, "DECK-UNDER"),
	]
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 2, "main_deck": deck},
		"p1": {"current_monster": Cards.monster(3, 22000)},  # rank 3 → reveal 3
	})
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"search_cards": [{"id": "RV-RED"}]}

	await s["effect_handler"].trigger_when_invading(0, 1, 2)

	assert_array(_ids(state.players[0].hand)).contains_exactly(["RV-RED"])
	assert_array(_ids(state.players[0].discard_pile)).contains_exactly_in_any_order(["RV-STR", "RV-MON"])
	assert_int(state.players[0].main_deck.size()).is_equal(1)
	assert_array(_ids(_calls_of(input, "search_cards")[0]["matching"])).contains_exactly(["RV-RED"])


## EBP03-011 <Enter> (monster): reveal deck-top cards equal to the opponent
## monster's rank, add up to 1 red + up to 1 blue battle card, discard the rest.
func test_ebp03_011_enter_reveals_and_adds_red_and_blue_battle() -> void:
	var card := Real.instance("EBP03-011")
	var red := Cards.battle(2, 3000, "RV-RED")
	var blue := _blue_battle("RV-BLUE")
	var deck: Array[Dictionary] = [
		red, blue,
		Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "RV-MON"),
		Cards.battle(1, 2000, "DECK-UNDER"),
	]
	var state := States.make_state({
		"p0": {"current_monster": card, "monster_zone": 2, "main_deck": deck},
		"p1": {"current_monster": Cards.monster(3, 22000)},  # rank 3 → reveal 3
	})
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"select_cards": [[red, blue]]}

	await s["effect_handler"].trigger_enter(0, card)

	assert_array(_ids(state.players[0].hand)).contains_exactly_in_any_order(["RV-RED", "RV-BLUE"])
	assert_array(_ids(state.players[0].discard_pile)).contains_exactly(["RV-MON"])
	assert_int(state.players[0].main_deck.size()).is_equal(1)
	var call := _calls_of(input, "select_cards")[0]
	assert_array(_ids(call["matching"])).contains_exactly_in_any_order(["RV-RED", "RV-BLUE"])
	assert_int(int(call["min"])).is_equal(0)
	assert_int(int(call["max"])).is_equal(2)


## EBP03-033 <Enter>: may discard 1 rank>=5 battle card from hand; if so,
## search the deck for "Space Beam" and add it to hand.
func test_ebp03_033_enter_discard_cost_then_search_space_beam(pay_cost: bool,
		test_parameters := [
			[true],
			[false],
		]) -> void:
	var card := Real.instance("EBP03-033")
	var beam := Real.instance("EBP03-069")  # named "Space Beam"
	var deck: Array[Dictionary] = [beam, Cards.battle(2, 3000, "DECK-BTL"), Cards.strategy(1, "DECK-STR")]
	var hand: Array[Dictionary] = [Cards.battle(5, 4000, "HAND-R5"), Cards.battle(2, 2000, "HAND-R2")]
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "hand": hand, "main_deck": deck}})
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {
		"select_hand_card": [0 if pay_cost else -1],
		"search_cards": [{"id": beam["id"]}],
	}

	await s["effect_handler"].trigger_enter(0, card)

	if pay_cost:
		assert_array(_calls_of(input, "select_hand_card")[0]["valid"]).contains_exactly([0])
		assert_array(_ids(state.players[0].discard_pile)).contains_exactly(["HAND-R5"])
		assert_array(_ids(state.players[0].hand)).contains_exactly_in_any_order(["HAND-R2", str(beam["id"])])
		assert_int(state.players[0].main_deck.size()).is_equal(2)
		assert_array(_ids(_calls_of(input, "search_cards")[0]["matching"])).contains_exactly([beam["id"]])
	else:
		assert_int(input.count_calls("search_cards")).is_equal(0)
		assert_array(_ids(state.players[0].hand)).contains_exactly_in_any_order(["HAND-R5", "HAND-R2"])
		assert_int(state.players[0].main_deck.size()).is_equal(3)
		assert_int(state.players[0].discard_pile.size()).is_equal(0)


## EBP03-055 <Enter>: may put up to 1 Mothra battle card from the discard
## pile on top of the deck.
func test_ebp03_055_enter_puts_mothra_battle_on_deck_top(take: bool,
		test_parameters := [
			[true],
			[false],
		]) -> void:
	var card := Real.instance("EBP03-055")
	var wanted := Real.instance("EBP03-055", 1)       # another Mothra battle card
	var mothra_monster := Real.instance("EBP03-021")  # Mothra trait but a monster
	var state := States.make_state({
		"p0": {"zone_cards": {2: card}, "main_deck": [
			Cards.battle(1, 2000, "DECK-0"), Cards.battle(1, 2000, "DECK-1"),
		]},
	})
	state.players[0].discard_pile.append_array([wanted, mothra_monster, Cards.battle(2, 3000, "DIS-BTL")])
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"search_cards": [{"id": wanted["id"]} if take else {}]}

	await s["effect_handler"].trigger_enter(0, card)

	assert_array(_ids(_calls_of(input, "search_cards")[0]["matching"])).contains_exactly([wanted["id"]])
	if take:
		# search_discard does not shuffle the deck, so the top placement is stable.
		assert_str(str(state.players[0].main_deck[0].get("id"))).is_equal(str(wanted["id"]))
		assert_int(state.players[0].main_deck.size()).is_equal(3)
		assert_int(state.players[0].discard_pile.size()).is_equal(2)
	else:
		assert_int(state.players[0].main_deck.size()).is_equal(2)
		assert_int(state.players[0].discard_pile.size()).is_equal(3)


## EBP03-070 (Base strategy) <Your Turn>: at the beginning of your counter
## phase, search the deck for a Weapon/Mech battle card and add it to hand.
func test_ebp03_070_counter_start_searches_weapon_or_mech_battle() -> void:
	var card := Real.instance("EBP03-070")
	var wanted := Real.instance("EBP03-031")  # Weapon battle card
	var deck: Array[Dictionary] = [
		wanted,
		Cards.battle(2, 3000, "DECK-PLAIN"),  # battle without the traits
		Cards.monster(1, 5000, [CardEnums.CardTrait.WEAPON], "DECK-WPN-MON"),  # trait but not battle
	]
	var state := States.make_state({"p0": {"strategy_zones": [card], "main_deck": deck}})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"search_cards": [{"id": wanted["id"]}]}

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_array(_ids(state.players[0].hand)).contains_exactly([wanted["id"]])
	assert_int(state.players[0].main_deck.size()).is_equal(2)
	assert_array(_ids(_calls_of(input, "search_cards")[0]["matching"])).contains_exactly([wanted["id"]])


## EBP04-061 <Enter>: with 4+ OTHER green battle cards in zones, search the
## deck for up to 1 green card and send it to the discard pile.
func test_ebp04_061_enter_green_gated_deck_search_to_discard(other_greens: int, expect_search: bool,
		test_parameters := [
			[4, true],
			[3, false],
		]) -> void:
	var card := Real.instance("EBP04-061")
	var zone_cards := {7: card}
	for i in range(other_greens):
		zone_cards[i] = _green_battle("ZONE-GREEN-%d" % i)
	var deck: Array[Dictionary] = [_green_battle("DECK-GREEN"), Cards.battle(2, 3000, "DECK-RED")]
	var state := States.make_state({"p0": {"zone_cards": zone_cards, "main_deck": deck}})
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"search_cards": [{"id": "DECK-GREEN"}]}

	await s["effect_handler"].trigger_enter(0, card)

	if expect_search:
		assert_array(_ids(state.players[0].discard_pile)).contains_exactly(["DECK-GREEN"])
		assert_int(state.players[0].main_deck.size()).is_equal(1)
		assert_array(_ids(_calls_of(input, "search_cards")[0]["matching"])).contains_exactly(["DECK-GREEN"])
	else:
		assert_int(input.count_calls("search_cards")).is_equal(0)
		assert_int(state.players[0].main_deck.size()).is_equal(2)
		assert_int(state.players[0].discard_pile.size()).is_equal(0)


## EBP04-088 (strategy) <Enter>: return up to 2 non-green battle cards from
## the discard pile to hand.
func test_ebp04_088_enter_returns_up_to_two_nongreen_battles() -> void:
	var card := Real.instance("EBP04-088")
	var b1 := Cards.battle(2, 3000, "DIS-RED-1")
	var b2 := Cards.battle(3, 4000, "DIS-RED-2")
	var state := States.make_state({"p0": {"strategy_zones": [card]}})
	state.players[0].discard_pile.append_array([
		b1, b2,
		_green_battle("DIS-GREEN"),    # battle but green
		Cards.strategy(1, "DIS-STR"),  # non-green but not a battle
	])
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"select_cards": [[b1, b2]]}

	await s["effect_handler"].trigger_enter(0, card)

	assert_array(_ids(state.players[0].hand)).contains_exactly_in_any_order(["DIS-RED-1", "DIS-RED-2"])
	assert_array(_ids(state.players[0].discard_pile)).contains_exactly_in_any_order(["DIS-GREEN", "DIS-STR"])
	var call := _calls_of(input, "select_cards")[0]
	assert_array(_ids(call["matching"])).contains_exactly_in_any_order(["DIS-RED-1", "DIS-RED-2"])
	assert_int(int(call["min"])).is_equal(0)
	assert_int(int(call["max"])).is_equal(2)


## ESD01-002 <When Invading> (monster): search the deck for up to 1 rank-III
## card named "Godzilla(2023)" with <Burst> and add it to hand.
func test_esd01_002_invading_searches_burst_godzilla_to_hand() -> void:
	var card := Real.instance("ESD01-002")
	var wanted := Real.instance("ESD01-006")      # Godzilla(2023) rank 3, Burst2
	var no_burst := Real.instance("ESD01-003")    # same name + rank 3, no Burst
	var wrong_rank := Real.instance("ESD01-005")  # Burst1 but rank 2
	var deck: Array[Dictionary] = [wanted, no_burst, wrong_rank, Cards.battle(2, 3000, "DECK-BTL")]
	var state := States.make_state({"p0": {"current_monster": card, "monster_zone": 2, "main_deck": deck}})
	var s := States.make_session(state)
	var input: ScriptedPlayerInput = s["input"]
	input.answers = {"search_cards": [{"id": wanted["id"]}]}

	await s["effect_handler"].trigger_when_invading(0, 1, 2)

	assert_array(_ids(state.players[0].hand)).contains_exactly([wanted["id"]])
	assert_int(state.players[0].main_deck.size()).is_equal(3)
	assert_array(_ids(_calls_of(input, "search_cards")[0]["matching"])) \
		.override_failure_message("ESD01-002: only the rank-III Burst Godzilla(2023) may be offered") \
		.contains_exactly([wanted["id"]])
