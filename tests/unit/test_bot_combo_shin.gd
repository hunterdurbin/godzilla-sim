extends GdUnitTestSuite

## BotComboShin.check — the counter-retreat path follows the engine's rank-up
## rule (5.15.1.2): only a monster the countered player could actually rank
## into counts. Hand-built cards; the rank-3 monster's "advances_opponent" bot
## tag comes from a synthetic effect, and a hand-built 2-step invader makes
## check() return a plan.

const States := preload("res://tests/fixtures/states.gd")
const Cards := preload("res://tests/fixtures/cards.gd")

const ADVANCES_OPPONENT := "test://advances_opponent"


class AdvancesOpponentEffect extends CardEffect:
	func get_bot_tags() -> Array[String]:
		return ["advances_opponent"]


## Bot (p1) at zone 5 on a rank-2 monster with `current_traits`, its monster
## deck holding only a rank-3 GODZILLA monster tagged "advances_opponent".
func _shin_plan(current_traits: Array) -> Dictionary:
	var rank_3 := Cards.monster(3, 9000, [CardEnums.CardTrait.GODZILLA], "T-MON-3")
	rank_3["effect_script"] = ADVANCES_OPPONENT
	var state := States.make_state({"p1": {
		"monster_zone": 5,
		"current_monster": Cards.monster(2, 7000, current_traits, "T-MON-2"),
		"monster_deck": [rank_3],
		"hand": [Cards.battle(1, 5000, "T-INV2", [], 2)],
	}})
	var session := States.make_session(state)
	var bot := BotPlayer.new()
	bot.game_state = state
	bot.effect_handler = session["effect_handler"]
	bot.rules_engine = session["rules"]
	bot.effect_handler.registry.register_for_test(ADVANCES_OPPONENT, AdvancesOpponentEffect.new())
	return BotComboShin.new().check(state.players[1], state.players[0], bot)


func test_counter_retreat_path_when_rank_up_shares_a_trait() -> void:
	# GODZILLA rank 2 → the GODZILLA rank 3 is a legal rank-up, so a counter
	# auto-plays it.
	var plan := _shin_plan([CardEnums.CardTrait.GODZILLA])
	assert_bool(plan.get("counter_retreat_path", false)).is_true()


func test_no_counter_retreat_path_when_rank_up_shares_no_trait() -> void:
	# MOTHRA rank 2 → the GODZILLA rank 3 shares no trait, so a counter can
	# never rank into it (5.15.1.2).
	var plan := _shin_plan([CardEnums.CardTrait.MOTHRA])
	assert_bool(plan.is_empty()).is_false()
	assert_bool(plan.get("counter_retreat_path", true)).is_false()
