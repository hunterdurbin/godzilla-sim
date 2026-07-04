extends GdUnitTestSuite

## Characterization tests for RulesEngine over neutral EffectQueries (fixture
## cards carry no effect scripts, so every modifier/blocking query returns its
## base value — the pure-rules behavior).

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")

var rules: RulesEngine


func test_empty_hand_only_pass() -> void:
	var state := States.make_state()
	rules = States.make_rules(state)
	assert_array(rules.get_valid_actions(state)).contains_exactly([CardEnums.ActionType.PASS])


func test_battle_card_playable_when_rank_within_opponent_zone() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1)]}, "p1": {"monster_zone": 1}})
	rules = States.make_rules(state)
	assert_array(rules.get_valid_actions(state)).contains([CardEnums.ActionType.PLAY_BATTLE])


func test_battle_card_blocked_when_rank_exceeds_opponent_zone() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(2)]}, "p1": {"monster_zone": 1}})
	rules = States.make_rules(state)
	assert_array(rules.get_valid_actions(state)).not_contains([CardEnums.ActionType.PLAY_BATTLE])


func test_playable_battle_cards_returns_matching_indices() -> void:
	var state := States.make_state({
		"p0": {"hand": [Cards.battle(1), Cards.monster(), Cards.battle(3), Cards.battle(2)]},
		"p1": {"monster_zone": 2},
	})
	rules = States.make_rules(state)
	var indices := rules.get_playable_battle_cards(state.players[0], state.players[1])
	assert_array(indices).contains_exactly([0, 3])


func test_valid_zones_exclude_own_monster_zone() -> void:
	var state := States.make_state({"p0": {"monster_zone": 3}})
	rules = States.make_rules(state)
	var zones := rules.get_valid_zones_for_battle_card(state.players[0], state.players[1])
	assert_array(zones).contains_exactly([0, 1, 3, 4, 5, 6, 7])


func test_can_play_battle_card_at_zone_rejects_monster_zone_and_out_of_range() -> void:
	var state := States.make_state({"p0": {"monster_zone": 1}, "p1": {"monster_zone": 4}})
	rules = States.make_rules(state)
	var card := Cards.battle(2)
	assert_bool(rules.can_play_battle_card_at_zone(card, 0, state.players[0], state.players[1])).is_false()
	assert_bool(rules.can_play_battle_card_at_zone(card, 1, state.players[0], state.players[1])).is_true()
	assert_bool(rules.can_play_battle_card_at_zone(card, 8, state.players[0], state.players[1])).is_false()
	assert_bool(rules.can_play_battle_card_at_zone(card, -1, state.players[0], state.players[1])).is_false()


func test_strategy_requires_rank_within_own_zone_and_empty_slot() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.strategy(2)], "monster_zone": 1}})
	rules = States.make_rules(state)
	assert_array(rules.get_playable_strategy_cards(state.players[0])).is_empty()

	state = States.make_state({"p0": {"hand": [Cards.strategy(2)], "monster_zone": 2}})
	rules = States.make_rules(state)
	assert_array(rules.get_playable_strategy_cards(state.players[0])).contains_exactly([0])

	# Both strategy zones occupied -> nothing playable.
	state = States.make_state({"p0": {
		"hand": [Cards.strategy(1)],
		"strategy_zones": [Cards.strategy(1, "S-A"), Cards.strategy(1, "S-B")],
	}})
	rules = States.make_rules(state)
	assert_array(rules.get_playable_strategy_cards(state.players[0])).is_empty()


func test_gain_rage_requires_monster_in_hand() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1)]}})
	rules = States.make_rules(state)
	assert_array(rules.get_valid_actions(state)).not_contains([CardEnums.ActionType.GAIN_RAGE])

	state = States.make_state({"p0": {"hand": [Cards.monster()]}})
	rules = States.make_rules(state)
	assert_array(rules.get_valid_actions(state)).contains([CardEnums.ActionType.GAIN_RAGE])
	assert_array(rules.get_monster_cards_for_rage(state.players[0])).contains_exactly([0])


func test_play_monster_requires_same_rank_and_trait_overlap() -> void:
	var godzilla_r1 := Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA])
	var rodan_r1 := Cards.monster(1, 5000, [CardEnums.CardTrait.RODAN])
	var godzilla_r2 := Cards.monster(2, 7000, [CardEnums.CardTrait.GODZILLA])
	var state := States.make_state({"p0": {
		"hand": [godzilla_r1, rodan_r1, godzilla_r2],
		"current_monster": Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA]),
	}})
	rules = States.make_rules(state)
	assert_array(rules.get_playable_monsters(state.players[0])).contains_exactly([0])


func test_play_monster_blocked_after_monster_played_this_turn() -> void:
	var state := States.make_state({"p0": {
		"hand": [Cards.monster()],
		"has_played_monster_this_turn": true,
	}})
	rules = States.make_rules(state)
	assert_array(rules.get_playable_monsters(state.players[0])).is_empty()
	assert_array(rules.get_valid_actions(state)).not_contains([CardEnums.ActionType.PLAY_MONSTER])


func test_invade_requires_invasion_icon_and_once_per_turn() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1, 5000, "T-BTL", [], 2)]}})
	rules = States.make_rules(state)
	assert_array(rules.get_valid_actions(state)).contains([CardEnums.ActionType.INVADE])
	assert_array(rules.get_discardable_cards_for_invade(state.players[0], state.players[1])).contains_exactly([0])

	state.players[0].has_invaded_this_turn = true
	assert_array(rules.get_valid_actions(state)).not_contains([CardEnums.ActionType.INVADE])
	assert_array(rules.get_discardable_cards_for_invade(state.players[0], state.players[1])).is_empty()


func test_invade_with_no_icon_card_unavailable() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1, 5000, "T-BTL", [], 0)]}})
	rules = States.make_rules(state)
	assert_array(rules.get_valid_actions(state)).not_contains([CardEnums.ActionType.INVADE])


func test_invade_allowed_at_zone_8_with_defender_as_discard_only() -> void:
	## A monster at zone 8 facing an opponent zone-8 battle card can still
	## invade: the action stays available as a discard-only invade (the
	## invasion resolver leaves the monster in place — no advancement, no win).
	var state := States.make_state({
		"p0": {"hand": [Cards.battle(1)], "monster_zone": 8},
		"p1": {"zone_cards": {7: Cards.battle(1, 5000, "DEF")}},
	})
	rules = States.make_rules(state)
	assert_array(rules.get_valid_actions(state)).contains([CardEnums.ActionType.INVADE])
	assert_array(rules.get_discardable_cards_for_invade(state.players[0], state.players[1])).contains_exactly([0])


func test_check_win_condition() -> void:
	var state := States.make_state()
	rules = States.make_rules(state)
	assert_int(rules.check_win_condition(state)).is_equal(-1)

	state.players[0].monster_zone = 9
	assert_int(rules.check_win_condition(state)).is_equal(0)

	# Defender in opponent zone 8 denies the win.
	state.players[1].push_zone_card(7, Cards.battle(1))
	assert_int(rules.check_win_condition(state)).is_equal(-1)


func test_check_counter_compares_cp_to_threat() -> void:
	var state := States.make_state({
		"p0": {"zone_cards": {0: Cards.battle(1, 5000)}},
		"p1": {"current_monster": Cards.monster(1, 5000), "rage": 0},
	})
	rules = States.make_rules(state)
	assert_bool(rules.check_counter(state.players[0], state.players[1])).is_true()

	state.players[1].rage = 1  # threat 5000 + 5000
	assert_bool(rules.check_counter(state.players[0], state.players[1])).is_false()


func test_can_opponent_rank_up_needs_next_rank_with_shared_trait() -> void:
	var state := States.make_state({"p1": {
		"current_monster": Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA]),
		"monster_deck": [Cards.monster(2, 7000, [CardEnums.CardTrait.RODAN])],
	}})
	rules = States.make_rules(state)
	assert_bool(rules.can_opponent_rank_up(state.players[1])).is_false()

	state.players[1].monster_deck.append(Cards.monster(2, 7000, [CardEnums.CardTrait.GODZILLA]))
	assert_bool(rules.can_opponent_rank_up(state.players[1])).is_true()
