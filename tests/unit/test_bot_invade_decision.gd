extends GdUnitTestSuite

## BotPlayer._decide_invade — regression coverage for the discard-only invade
## at a defended zone 8. The rules engine offers INVADE there (legal hand-cycle:
## cost paid, no advancement), but the bot deliberately skips it.

const States := preload("res://tests/fixtures/states.gd")
const Cards := preload("res://tests/fixtures/cards.gd")


func _make_bot(bot_opts: Dictionary, opponent_opts: Dictionary = {}) -> BotPlayer:
	var bot := BotPlayer.new()
	bot.game_state = States.make_state({"p0": opponent_opts, "p1": bot_opts})
	bot.rules_engine = States.make_rules(bot.game_state)
	return bot  # bot_player_id defaults to 1, so p0 is the opponent


func test_skips_discard_only_invade_at_defended_zone_8() -> void:
	var bot := _make_bot(
		{"hand": [Cards.battle(1)], "monster_zone": 8},
		{"zone_cards": {7: Cards.battle(1, 5000, "DEF")}},
	)
	var player := bot.game_state.players[1]
	var opponent := bot.game_state.players[0]
	# The engine offers the discard-only invade...
	assert_array(bot.rules_engine.get_discardable_cards_for_invade(player, opponent)) \
		.contains_exactly([0])
	# ...but the bot declines it.
	assert_array(bot._decide_invade(player, opponent)).is_empty()


func test_invades_at_undefended_zone_8() -> void:
	# Same state minus the defender: the skip is about the zone-8 battle card,
	# not zone 8 itself.
	var bot := _make_bot({"hand": [Cards.battle(1)], "monster_zone": 8})
	var player := bot.game_state.players[1]
	var opponent := bot.game_state.players[0]
	var result := bot._decide_invade(player, opponent)
	assert_array(result).is_not_empty()
	assert_int(result[0]).is_equal(CardEnums.ActionType.INVADE)
	assert_int(result[1]["hand_index"]).is_equal(0)
