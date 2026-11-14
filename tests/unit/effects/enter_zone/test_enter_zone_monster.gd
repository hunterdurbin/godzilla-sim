extends GdUnitTestSuite

## EnterZone, monster plays (hunterdurbin/godzilla-sim-issue-tracker#35 rows 14–16):
## the Play action, an effect play from the monster deck and the counter
## rank-up all make a card the new invading monster (5.11.2), so each fires
## its <Enter> and the "when your monster card is played" watchers. Burst
## (12.5.2.1): the Burst card goes to the discard pile at the end phase even
## when a later play has buried it.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Probe := preload("res://tests/fixtures/effects/enter_zone_probe.gd")

const GODZILLA := CardEnums.CardTrait.GODZILLA


func _session(opts: Dictionary) -> Dictionary:
	var state := States.make_state(opts)
	var s := States.make_session(state)
	s["state"] = state
	s["probe"] = Probe.register(s["effect_handler"])
	return s


func _teardown(s: Dictionary) -> void:
	var ah: ActionHandler = s["action_handler"]
	ah.teardown()
	var handler: EffectHandler = s["effect_handler"]
	handler.teardown()


## Resolve the check timing and return what the probe saw.
func _resolve(s: Dictionary) -> Array:
	var handler: EffectHandler = s["effect_handler"]
	await handler.check_timing.resolve()
	return s["probe"].seen


## A monster card whose abilities the probe records.
func _probe_monster(rank: int, id: String) -> Dictionary:
	var card := Cards.monster(rank, 4000 + rank * 2000, [GODZILLA], id)
	card["effect_script"] = Probe.PATH
	return card


func test_the_play_action_fires_enter_and_monster_played_watchers() -> void:
	var s := _session({"p0": {
		"current_monster": Cards.monster(1, 6000, [GODZILLA], "OLD"),
		"hand": [_probe_monster(1, "NEW")],
		"monster_zone": 2,
		"zone_cards": {4: Probe.card("WATCH")},
	}})
	var p0: PlayerState = s["state"].players[0]

	await s["action_handler"].execute(CardEnums.ActionType.PLAY_MONSTER, {"hand_index": 0}, s["state"])

	assert_str(str(p0.current_monster.get("id"))).is_equal("NEW")
	assert_int(p0.rage).is_equal(1)
	assert_array(await _resolve(s)).contains_exactly_in_any_order([
		"enter:NEW:effect=false:evo=false",
		"monster@WATCH:OLD>NEW",
	])
	_teardown(s)


func test_the_counter_rank_up_is_a_play_and_fires_monster_played_watchers() -> void:
	# Q288: "You can no longer play a monster card, so your opponent wins by
	# Counter Victory." — the rank-up is a play (5.11.2).
	var rank_up := _probe_monster(2, "RANK-UP")
	var s := _session({
		"p0": {"monster_zone": 2, "zone_cards": {0: Cards.battle(1, 9000)}},
		"p1": {
			"current_monster": Cards.monster(1, 5000, [GODZILLA], "OLD"),
			"monster_zone": 7,
			"monster_deck": [rank_up],
			"zone_cards": {0: Probe.card("WATCH")},
		},
	})
	var p1: PlayerState = s["state"].players[1]
	var played: Array = []
	s["events"].monster_played.connect(func(pid: int, old: Dictionary, new: Dictionary) -> void:
		played.append("%d:%s>%s" % [pid, old.get("id"), new.get("id")]))

	await s["action_handler"].resolve_counter(s["state"])

	assert_array(played).contains_exactly(["1:OLD>RANK-UP"])
	assert_str(str(p1.current_monster.get("id"))).is_equal("RANK-UP")
	assert_bool(p1.monster_deck.is_empty()).is_true()
	assert_array(await _resolve(s)).contains_exactly_in_any_order([
		"enter:RANK-UP:effect=true:evo=false",
		"monster@WATCH:OLD>RANK-UP",
	])
	_teardown(s)


func test_a_burst_card_buried_by_an_effect_play_is_discarded_and_the_new_monster_stays() -> void:
	# 12.5.2.1: "Even if this card is not the topmost card at the beginning of
	# the end phase for any reason, the card is still sent to the discard pile."
	var pre_burst := Cards.monster(2, 7000, [GODZILLA], "PRE")
	var burst := _probe_monster(3, "BURST")
	var played := Cards.monster(4, 12000, [GODZILLA], "PLAYED")
	var s := _session({"p0": {"current_monster": burst, "monster_deck": [played]}})
	var p0: PlayerState = s["state"].players[0]
	p0.burst_monster = burst
	p0.pre_burst_monster = pre_burst
	p0.monster_stack = [pre_burst]
	var ah: ActionHandler = s["action_handler"]

	ah.play_monster_from_effect(s["state"], 0, played)
	await ah.execute_end_phase_burst_discard(s["state"])

	assert_str(str(p0.current_monster.get("id"))).is_equal("PLAYED")
	assert_array(p0.monster_stack.map(func(c: Dictionary) -> String: return c.get("id"))) \
			.contains_exactly(["PRE"])
	assert_array(p0.discard_pile.map(func(c: Dictionary) -> String: return c.get("id"))) \
			.contains_exactly(["BURST"])
	assert_bool(p0.burst_monster.is_empty()).is_true()
	assert_bool(p0.pre_burst_monster.is_empty()).is_true()
	assert_array(s["probe"].seen).contains(["burst-discard:BURST"])
	_teardown(s)


func test_a_burst_card_still_on_top_restores_the_monster_under_it_without_entering() -> void:
	# 12.5.3 / Q107: the restored monster card does not enter again.
	var pre_burst := _probe_monster(2, "PRE")
	var burst := Cards.monster(3, 9000, [GODZILLA], "BURST")
	var s := _session({"p0": {"current_monster": burst, "monster_zone": 2,
			"zone_cards": {4: Probe.card("WATCH")}}})
	var p0: PlayerState = s["state"].players[0]
	p0.burst_monster = burst
	p0.pre_burst_monster = pre_burst
	p0.monster_stack = [pre_burst]

	await s["action_handler"].execute_end_phase_burst_discard(s["state"])

	assert_str(str(p0.current_monster.get("id"))).is_equal("PRE")
	assert_bool(p0.monster_stack.is_empty()).is_true()
	assert_array(await _resolve(s)).is_empty()
	_teardown(s)


func test_the_activate_action_places_the_strategy_and_fires_its_enter() -> void:
	var strategy := Cards.strategy(1, "STRAT")
	strategy["effect_script"] = Probe.PATH
	var s := _session({"p0": {"hand": [strategy]}})
	var p0: PlayerState = s["state"].players[0]
	var placed: Array = []
	s["events"].strategy_card_played.connect(func(_pid: int, card: Dictionary, idx: int) -> void:
		placed.append("%s@%d" % [card.get("id"), idx]))

	await s["action_handler"].execute(CardEnums.ActionType.PLAY_STRATEGY, {"hand_index": 0}, s["state"])

	assert_bool(p0.hand.is_empty()).is_true()
	assert_array(placed).contains_exactly(["STRAT@0"])
	assert_array(await _resolve(s)).contains_exactly(["enter:STRAT:effect=false:evo=false"])
	_teardown(s)
