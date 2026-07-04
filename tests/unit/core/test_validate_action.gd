extends GdUnitTestSuite

## Characterization tests for RulesEngine.validate_action — the server-side
## anti-cheat gate. Must stay pure and synchronous.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")

var rules: RulesEngine


func test_pass_always_valid() -> void:
	var state := States.make_state()
	rules = States.make_rules(state)
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PASS, {})).is_true()


func test_play_battle_accepts_valid_index_and_zone() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1)]}})
	rules = States.make_rules(state)
	var params := {"hand_index": 0, "zone_index": 1}
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_BATTLE, params)).is_true()


func test_play_battle_rejects_own_monster_zone() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1)], "monster_zone": 1}})
	rules = States.make_rules(state)
	var params := {"hand_index": 0, "zone_index": 0}
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_BATTLE, params)).is_false()


func test_play_battle_rejects_stale_hand_index() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1)]}})
	rules = States.make_rules(state)
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_BATTLE, {"hand_index": 5, "zone_index": 1})).is_false()
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_BATTLE, {"hand_index": -1, "zone_index": 1})).is_false()


func test_play_battle_rejects_missing_params() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1)]}})
	rules = States.make_rules(state)
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_BATTLE, {})).is_false()


func test_play_battle_rejects_non_battle_index() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.monster(), Cards.battle(1)]}})
	rules = States.make_rules(state)
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_BATTLE, {"hand_index": 0, "zone_index": 1})).is_false()
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_BATTLE, {"hand_index": 1, "zone_index": 1})).is_true()


func test_play_strategy_validates_index() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.strategy(1), Cards.battle(1)]}})
	rules = States.make_rules(state)
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": 0})).is_true()
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": 1})).is_false()


func test_gain_rage_validates_monster_index() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1), Cards.monster()]}})
	rules = States.make_rules(state)
	assert_bool(rules.validate_action(state, CardEnums.ActionType.GAIN_RAGE, {"hand_index": 1})).is_true()
	assert_bool(rules.validate_action(state, CardEnums.ActionType.GAIN_RAGE, {"hand_index": 0})).is_false()


func test_play_monster_validates_index() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.monster(1)]}})
	rules = States.make_rules(state)
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_MONSTER, {"hand_index": 0})).is_true()
	assert_bool(rules.validate_action(state, CardEnums.ActionType.PLAY_MONSTER, {"hand_index": 1})).is_false()


func test_invade_validates_invasion_icon_index() -> void:
	var state := States.make_state({"p0": {"hand": [
		Cards.battle(1, 5000, "A", [], 0),
		Cards.battle(1, 5000, "B", [], 1),
	]}})
	rules = States.make_rules(state)
	assert_bool(rules.validate_action(state, CardEnums.ActionType.INVADE, {"hand_index": 1})).is_true()
	assert_bool(rules.validate_action(state, CardEnums.ActionType.INVADE, {"hand_index": 0})).is_false()


func test_invade_valid_at_defended_zone_8() -> void:
	# Discard-only invade: monster at 8 with an opponent zone-8 battle card.
	var state := States.make_state({
		"p0": {"hand": [Cards.battle(1)], "monster_zone": 8},
		"p1": {"zone_cards": {7: Cards.battle(1, 5000, "DEF")}},
	})
	rules = States.make_rules(state)
	assert_bool(rules.validate_action(state, CardEnums.ActionType.INVADE, {"hand_index": 0})).is_true()


func test_action_not_in_valid_set_rejected() -> void:
	# Empty hand: only PASS is valid, every other action must be rejected.
	var state := States.make_state()
	rules = States.make_rules(state)
	for action: CardEnums.ActionType in [
		CardEnums.ActionType.PLAY_BATTLE,
		CardEnums.ActionType.PLAY_STRATEGY,
		CardEnums.ActionType.GAIN_RAGE,
		CardEnums.ActionType.PLAY_MONSTER,
		CardEnums.ActionType.INVADE,
	]:
		assert_bool(rules.validate_action(state, action, {"hand_index": 0, "zone_index": 1})).is_false()


func test_validate_action_has_no_side_effects() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.battle(1), Cards.monster()]}})
	rules = States.make_rules(state)
	var hand_before := state.players[0].hand.duplicate(true)
	rules.validate_action(state, CardEnums.ActionType.PLAY_BATTLE, {"hand_index": 0, "zone_index": 1})
	rules.validate_action(state, CardEnums.ActionType.GAIN_RAGE, {"hand_index": 1})
	assert_array(state.players[0].hand).is_equal(hand_before)
	assert_int(state.players[0].monster_zone).is_equal(1)
	assert_int(state.players[0].rage).is_equal(0)
