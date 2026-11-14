extends GdUnitTestSuite

## RulesEngine + effect-driven queries via synthetic CardEffects.
## Pins the two behavior unifications from deduplicating get_valid_actions
## (the old _can_play_any_* helpers ignored these modifiers):
##  1. A strategy-hand rank modifier (EBP04-068 style) makes PLAY_STRATEGY
##     appear in get_valid_actions.
##  2. An alternate monster play cost (EBP04-012 style) makes PLAY_MONSTER
##     appear in get_valid_actions.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


class StrategyDiscountEffect:
	extends CardEffect
	func get_strategy_hand_rank_modifier(_ctx: EffectContext, _card: Dictionary, _target_player_id: int) -> int:
		return -1


class AlternateMonsterPlayEffect:
	extends CardEffect
	func can_play_as_monster(_ctx: EffectContext) -> bool:
		return true


func _rules_with_effect(state: GameState, script_path: String, effect: CardEffect, triggers: Array) -> RulesEngine:
	var handler := EffectHandler.new()
	handler.setup(state, PlayerInput.new())
	handler.registry.register_for_test(script_path, effect, triggers)
	var rules := RulesEngine.new()
	rules.queries = handler.queries
	return rules


func test_strategy_hand_rank_modifier_enables_play_strategy() -> void:
	# Rank-2 strategy in hand, monster at zone 1: unplayable by base rules.
	var strategy := Cards.strategy(2)
	var modifier_source := Cards.battle(1, 5000, "MOD")
	modifier_source["effect_script"] = "test://strategy_discount"
	var state := States.make_state({"p0": {
		"hand": [strategy],
		"monster_zone": 1,
		"zone_cards": {3: modifier_source},
	}})
	var rules := _rules_with_effect(state, "test://strategy_discount", StrategyDiscountEffect.new(), [])

	assert_array(rules.get_playable_strategy_cards(state.players[0])).contains_exactly([0])
	# The unification fix: PLAY_STRATEGY appears in valid_actions too.
	assert_array(rules.get_valid_actions(state)).contains([CardEnums.ActionType.PLAY_STRATEGY])


func test_alternate_monster_play_enables_play_monster() -> void:
	# Rank-3 monster on a rank-1 current monster: rank mismatch (and no burst)
	# makes it unplayable by base rules; the alternate cost allows it.
	var alt_monster := Cards.monster(3, 9000, [CardEnums.CardTrait.GODZILLA], "ALT")
	alt_monster["effect_script"] = "test://alt_monster_play"
	var state := States.make_state({"p0": {
		"hand": [alt_monster],
		"current_monster": Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA]),
	}})
	var rules := _rules_with_effect(state, "test://alt_monster_play", AlternateMonsterPlayEffect.new(), ["can_play_as_monster"])

	assert_array(rules.get_playable_monsters(state.players[0])).contains_exactly([0])
	# The unification fix: PLAY_MONSTER appears in valid_actions too.
	assert_array(rules.get_valid_actions(state)).contains([CardEnums.ActionType.PLAY_MONSTER])


func test_burst_rank_enables_play_monster() -> void:
	var burst_monster := Cards.monster(3, 9000, [CardEnums.CardTrait.GODZILLA], "BURST")
	burst_monster["effect_script"] = "test://burst"
	var burst_effect := CardEffect.new()  # base get_burst_rank() == -1
	var state := States.make_state({"p0": {
		"hand": [burst_monster],
		"current_monster": Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA]),
	}})
	var rules := _rules_with_effect(state, "test://burst", burst_effect, [])
	# Base effect has no burst -> rank mismatch keeps it unplayable.
	assert_array(rules.get_playable_monsters(state.players[0])).is_empty()


func test_alternate_monster_play_bridges_rank_up_traits() -> void:
	# EBP04-033/034 style: the next-rank monster shares no trait with the
	# current one, but its alternate play cost permits the rank-up.
	var bridged := Cards.monster(2, 7000, [CardEnums.CardTrait.RODAN], "BRIDGE")
	bridged["effect_script"] = "test://alt_monster_play"
	var state := States.make_state({"p1": {
		"current_monster": Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA]),
		"monster_deck": [Cards.monster(2, 7000, [CardEnums.CardTrait.RODAN]), bridged],
	}})
	var rules := _rules_with_effect(state, "test://alt_monster_play", AlternateMonsterPlayEffect.new(), ["can_play_as_monster"])

	assert_array(rules.get_rank_up_candidates(state.players[1])).contains_exactly([1])


func test_bot_rank_up_judgement_honours_alternate_monster_play() -> void:
	# The bot's "can't rank up while countered" judgement must match the
	# engine's rank-up rule: a bridged next-rank monster is a live rank-up,
	# so countering does not win the game.
	var bridged := Cards.monster(2, 7000, [CardEnums.CardTrait.RODAN], "BRIDGE")
	bridged["effect_script"] = "test://alt_monster_play"
	var state := States.make_state({"p1": {
		"current_monster": Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA]),
		"monster_deck": [bridged],
	}})
	var rules := _rules_with_effect(state, "test://alt_monster_play", AlternateMonsterPlayEffect.new(), ["can_play_as_monster"])

	assert_bool(rules.can_opponent_rank_up(state.players[1])).is_true()
