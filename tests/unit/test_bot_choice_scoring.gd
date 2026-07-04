extends GdUnitTestSuite

## BotPlayer._score_choice_options — the keyword scorer behind
## choice_pick_mode 2 (default/HARD). Regression coverage for optional
## "you may" effects with a self-cost (EBP04-064 Jet Jaguar): the bot
## must be able to pick Skip when the payoff isn't there.

const States := preload("res://tests/fixtures/states.gd")
const Cards := preload("res://tests/fixtures/cards.gd")

const JET_JAGUAR_OPTIONS: Array[String] = [
	"Destroy this card to reduce opponent's Rage by 3",
	"Skip",
]


func _make_bot(opponent_opts: Dictionary = {}) -> BotPlayer:
	var bot := BotPlayer.new()
	bot.game_state = States.make_state({"p0": opponent_opts})
	return bot  # bot_player_id defaults to 1, so p0 is the opponent


func test_self_destroy_skipped_when_opponent_has_no_rage() -> void:
	var bot := _make_bot({"rage": 0})
	assert_int(bot._score_choice_options(JET_JAGUAR_OPTIONS)).is_equal(1)


func test_self_destroy_skipped_when_payoff_too_small() -> void:
	var bot := _make_bot({"rage": 1})
	assert_int(bot._score_choice_options(JET_JAGUAR_OPTIONS)).is_equal(1)


func test_self_destroy_taken_when_opponent_rage_is_high() -> void:
	var bot := _make_bot({"rage": 5})
	assert_int(bot._score_choice_options(JET_JAGUAR_OPTIONS)).is_equal(0)


func test_opponent_destruction_still_beats_skip() -> void:
	var bot := _make_bot({"zone_cards": {2: Cards.battle(4)}})
	var options: Array[String] = [
		"Destroy 1 opponent card of rank 4 or lower",
		"Skip",
	]
	assert_int(bot._score_choice_options(options)).is_equal(0)
