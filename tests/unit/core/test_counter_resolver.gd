extends GdUnitTestSuite

## CounterResolver: the four outcome branches, retreat zones, rank-up via
## PlayerInput, and loss when no rank-up exists. The counter numbers and
## rank-up eligibility themselves are tested on RulesEngine.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func test_counter_success_retreats_and_ranks_up() -> void:
	var state := States.make_state({
		"p0": {"monster_zone": 2, "zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {
			"current_monster": Cards.monster(1, 5000),
			"monster_zone": 7,
			"monster_deck": Cards.monster_line(),
		},
	})
	var input := ScriptedPlayerInput.new()
	var session := States.make_session(state, input)
	var outcomes: Array = []
	session["events"].counter_succeeded.connect(func(_pid: int, _cp: int, _t: int, _rt: int, _et: int) -> void: outcomes.append("success"))

	await session["action_handler"].resolve_counter(state)

	assert_array(outcomes).contains_exactly(["success"])
	assert_int(state.players[1].monster_zone).is_equal(4)  # 7 -> 4 (5.15.1.1)
	# Ranked up to the rank-2 monster from the deck (default input picks first valid).
	assert_int(state.players[1].current_monster.get("rank", 0)).is_equal(2)
	assert_int(input.count_calls("choose_rankup")).is_equal(1)
	# Old monster pushed under the new one.
	assert_int(state.players[1].monster_stack.size()).is_equal(1)


func test_counter_failure_no_movement() -> void:
	var state := States.make_state({
		"p0": {"monster_zone": 2, "zone_cards": {0: Cards.battle(1, 1000)}},
		"p1": {"current_monster": Cards.monster(1, 5000), "monster_zone": 7},
	})
	var session := States.make_session(state)
	var outcomes: Array = []
	session["events"].counter_failed.connect(func(_pid: int, _cp: int, _t: int, _rt: int, _et: int) -> void: outcomes.append("failed"))

	await session["action_handler"].resolve_counter(state)

	assert_array(outcomes).contains_exactly(["failed"])
	assert_int(state.players[1].monster_zone).is_equal(7)
	assert_int(state.players[1].current_monster.get("rank", 0)).is_equal(1)


func test_counter_zones_1_to_5_do_not_retreat() -> void:
	var state := States.make_state({
		"p0": {"monster_zone": 2, "zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {
			"current_monster": Cards.monster(1, 5000),
			"monster_zone": 3,
			"monster_deck": Cards.monster_line(),
		},
	})
	var session := States.make_session(state)
	await session["action_handler"].resolve_counter(state)
	assert_int(state.players[1].monster_zone).is_equal(3)  # zones 1-5 stay put
	assert_int(state.players[1].current_monster.get("rank", 0)).is_equal(2)  # still ranks up


func test_counter_victory_when_monster_deck_empty() -> void:
	var state := States.make_state({
		"p0": {"monster_zone": 2, "zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {"current_monster": Cards.monster(1, 5000), "monster_deck": []},
	})
	var session := States.make_session(state)
	var game_overs: Array = []
	state.game_over.connect(func(winner_id: int, reason: String) -> void: game_overs.append([winner_id, reason]))

	await session["action_handler"].resolve_counter(state)

	assert_int(game_overs.size()).is_equal(1)
	assert_int(game_overs[0][0]).is_equal(0)
	assert_str(str(game_overs[0][1])).is_equal("STR_LOG_REASON_COUNTER_VICTORY")


func test_counter_victory_when_no_valid_rankup() -> void:
	# Deck has a rank-2 monster but with no shared trait -> no valid target.
	var state := States.make_state({
		"p0": {"monster_zone": 2, "zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {
			"current_monster": Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA]),
			"monster_deck": [Cards.monster(2, 7000, [CardEnums.CardTrait.RODAN])],
		},
	})
	var session := States.make_session(state)
	var game_overs: Array = []
	state.game_over.connect(func(winner_id: int, _reason: String) -> void: game_overs.append(winner_id))

	await session["action_handler"].resolve_counter(state)

	assert_array(game_overs).contains_exactly([0])


func test_rankup_uses_scripted_choice() -> void:
	# Two valid rank-2 monsters; the script picks deck index 1.
	var state := States.make_state({
		"p0": {"monster_zone": 2, "zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {
			"current_monster": Cards.monster(1, 5000),
			"monster_zone": 6,
			"monster_deck": [
				Cards.monster(2, 7000, [CardEnums.CardTrait.GODZILLA], "R2-A"),
				Cards.monster(2, 7000, [CardEnums.CardTrait.GODZILLA], "R2-B"),
			],
		},
	})
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_rankup": [1]}
	var session := States.make_session(state, input)

	await session["action_handler"].resolve_counter(state)

	assert_str(str(state.players[1].current_monster.get("id"))).is_equal("R2-B")
	assert_int(state.players[1].monster_zone).is_equal(5)  # 6 -> 5


func test_force_counter_targets_specific_player() -> void:
	var state := States.make_state({
		"p0": {
			"current_monster": Cards.monster(1, 5000),
			"monster_zone": 8,
			"monster_deck": Cards.monster_line(),
		},
	})
	var session := States.make_session(state)
	await session["action_handler"].force_counter(state, 0)
	assert_int(state.players[0].monster_zone).is_equal(3)  # 8 -> 3
	assert_int(state.players[0].current_monster.get("rank", 0)).is_equal(2)


# --- Counter retreat crush (11.3 interrupt, 11.1.2.1) before the new <Enter> ---
# The crush happens at the retreat; the crushed card's <Revenge> and the new
# monster's <Enter> then share the 7.4.4 check timing's pool. Q250: "If both
# the monster and the battle card with 【Revenge】 belong to the same player,
# that player chooses the order in which to resolve them."

const REVENGE := "test://counter_retreat_revenge"
const ENTER := "test://counter_retreat_enter"


## Shared log for the crushed card's <Revenge> and the new monster's <Enter>.
## The <Enter> records whether the retreat zone (zone 4 → index 3) still
## holds a battle card when it resolves.
class RecordRetreat:
	extends CardEffect
	var seen: Array[String] = []
	var state: GameState

	func on_revenge(ctx: EffectContext) -> void:
		seen.append("revenge:%s" % ctx.card_data.get("id"))

	func on_enter(_ctx: EffectContext) -> void:
		seen.append("enter:zone4_occupied=%s" % state.players[1].zone_has_cards(3))


func _retreat_onto_revenge_state() -> GameState:
	var revenge := Cards.battle(1, 3000, "P1-REV")
	revenge["effect_script"] = REVENGE
	var line := Cards.monster_line()
	line[1]["effect_script"] = ENTER
	return States.make_state({
		"p0": {"monster_zone": 2, "zone_cards": {0: Cards.battle(1, 30000)}},
		"p1": {
			"current_monster": line[0],
			"monster_zone": 7,
			"monster_deck": line.slice(1),
			"zone_cards": {3: revenge},
		},
	})


func _register_retreat_recorder(session: Dictionary, state: GameState) -> RecordRetreat:
	var effect := RecordRetreat.new()
	effect.state = state
	var handler: EffectHandler = session["effect_handler"]
	handler.registry.register_for_test(REVENGE, effect, ["on_revenge"])
	handler.registry.register_for_test(ENTER, effect, ["on_enter"])
	return effect


func test_counter_retreat_crushes_before_new_monster_enter() -> void:
	var state := _retreat_onto_revenge_state()
	var session := States.make_session(state)
	var effect := _register_retreat_recorder(session, state)

	await session["action_handler"].resolve_counter(state)
	await session["effect_handler"].check_timing.resolve() # 7.4.4

	var p1 := state.players[1]
	assert_int(p1.monster_zone).is_equal(4)  # 7 -> 4
	assert_bool(p1.zone_has_cards(3)).is_false()
	assert_array(p1.discard_pile.map(func(c: Dictionary) -> String: return c.get("id"))) \
		.contains_exactly(["P1-REV"])
	assert_array(effect.seen).contains_exactly([
		"revenge:P1-REV",
		"enter:zone4_occupied=false",
	])


func test_counter_retreat_owner_orders_revenge_and_enter() -> void:
	# Q250: the countered player picks; here <Enter> first. The crush has
	# already happened, so zone 4 is empty either way.
	var state := _retreat_onto_revenge_state()
	var input := ScriptedPlayerInput.new()
	input.answers = {"choose_option": [1]}
	var session := States.make_session(state, input)
	var effect := _register_retreat_recorder(session, state)

	await session["action_handler"].resolve_counter(state)
	assert_array(effect.seen).is_empty()  # both wait in standby
	await session["effect_handler"].check_timing.resolve() # 7.4.4

	assert_array(effect.seen).contains_exactly([
		"enter:zone4_occupied=false",
		"revenge:P1-REV",
	])
	assert_int(input.calls_of("choose_option")[0]["player_id"]).is_equal(1)


func test_force_counter_retreat_crushes_before_new_monster_enter() -> void:
	var state := _retreat_onto_revenge_state()
	var session := States.make_session(state)
	var effect := _register_retreat_recorder(session, state)

	await session["action_handler"].force_counter(state, 1)
	await session["effect_handler"].check_timing.resolve() # 7.4.4

	assert_bool(state.players[1].zone_has_cards(3)).is_false()
	assert_array(effect.seen).contains_exactly([
		"revenge:P1-REV",
		"enter:zone4_occupied=false",
	])
