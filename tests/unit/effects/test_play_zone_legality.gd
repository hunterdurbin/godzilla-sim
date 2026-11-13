extends GdUnitTestSuite

## Play-zone legality (5.11.1.1): a battle card an effect plays into a
## specific zone that holds its master's invading monster is not played.
## Every engine play primitive enforces this, so card scripts never check
## monster_zone themselves; can_play_in_zone lets them offer legal zones only.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")

const MONSTER_ZONE_IDX := 3  # monster in zone 4


func _setup(opts: Dictionary = {}) -> Dictionary:
	var p0: Dictionary = {"monster_zone": MONSTER_ZONE_IDX + 1}
	p0.merge(opts)
	var state := States.make_state({"p0": p0})
	var s := States.make_session(state)
	s["state"] = state
	return s


func test_can_play_in_zone_excludes_the_monsters_zone() -> void:
	var s := _setup()
	var handler: EffectHandler = s["effect_handler"]
	assert_bool(handler.can_play_in_zone(0, MONSTER_ZONE_IDX)).is_false()
	assert_bool(handler.can_play_in_zone(0, MONSTER_ZONE_IDX - 1)).is_true()
	# The opponent's monster doesn't restrict this player's zones.
	assert_bool(handler.can_play_in_zone(1, MONSTER_ZONE_IDX)).is_true()


func test_play_from_hand_into_monster_zone_is_not_played() -> void:
	var card := Cards.battle(1, 3000, "HAND")
	var s := _setup({"hand": [card]})
	var p0: PlayerState = s["state"].players[0]

	var played: bool = await s["effect_handler"].play_battle_card_from_hand(0, card, MONSTER_ZONE_IDX)

	assert_bool(played).is_false()
	assert_bool(p0.zone_has_cards(MONSTER_ZONE_IDX)).is_false()
	assert_array(p0.hand).contains_exactly([card])


func test_play_from_deck_into_monster_zone_is_not_played() -> void:
	var card := Cards.battle(1, 3000, "DECK")
	var s := _setup()
	var p0: PlayerState = s["state"].players[0]

	var played: bool = await s["effect_handler"].play_battle_card_from_deck(0, card, MONSTER_ZONE_IDX)

	assert_bool(played).is_false()
	assert_bool(p0.zone_has_cards(MONSTER_ZONE_IDX)).is_false()
	# Not played → it never left the deck (callers have already taken it out).
	assert_array(p0.main_deck).contains([card])


func test_play_from_discard_into_monster_zone_is_not_played() -> void:
	var card := Cards.battle(1, 3000, "DISCARD")
	var s := _setup()
	var p0: PlayerState = s["state"].players[0]
	p0.discard_pile.append(card)

	var zone: int = await s["effect_handler"].play_from_discard(0, card, MONSTER_ZONE_IDX)

	assert_int(zone).is_equal(-1)
	assert_bool(p0.zone_has_cards(MONSTER_ZONE_IDX)).is_false()
	assert_array(p0.discard_pile).contains_exactly([card])


func test_token_into_monster_zone_is_not_played() -> void:
	var s := _setup()
	var p0: PlayerState = s["state"].players[0]

	var placed: bool = await s["effect_handler"].create_token_in_zone(p0, "EBP02-T03", MONSTER_ZONE_IDX)

	assert_bool(placed).is_false()
	assert_bool(p0.zone_has_cards(MONSTER_ZONE_IDX)).is_false()


func test_play_into_a_legal_zone_still_plays() -> void:
	var card := Cards.battle(1, 3000, "HAND")
	var s := _setup({"hand": [card]})
	var p0: PlayerState = s["state"].players[0]

	var played: bool = await s["effect_handler"].play_battle_card_from_hand(0, card, 0)

	assert_bool(played).is_true()
	assert_str(str(p0.get_zone_top_card(0).get("id"))).is_equal("HAND")
	assert_array(p0.hand).is_empty()
