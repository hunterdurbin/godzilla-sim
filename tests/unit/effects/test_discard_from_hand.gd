extends GdUnitTestSuite

## CardMover.discard_from_hand (hunterdurbin/godzilla-sim-issue-tracker#35
## rows 22-24): every discard from hand — the Gain Rage action, the invasion
## cost, an effect — is one operation. It takes the cards out of the hand,
## puts them in the discard pile and submits all their watchers in one batch;
## an effect discard also writes one log line (#9).

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")

const PROBE_PATH := "test://discard_probe"


## Records which discard hooks resolved, in resolution order.
class DiscardProbe:
	extends CardEffect
	var fired: Array = []

	func on_discard_from_hand(ctx: EffectContext) -> void:
		fired.append("self:" + str(ctx.card_data.get("id", "")))

	func on_hand_card_discarded(ctx: EffectContext, discarded_card: Dictionary) -> void:
		fired.append("watch:%s<-%s" % [ctx.card_data.get("id", ""), discarded_card.get("id", "")])

	func on_discarded_for_invasion(ctx: EffectContext) -> bool:
		fired.append("invasion:" + str(ctx.card_data.get("id", "")))
		return false


func _probed(card: Dictionary) -> Dictionary:
	card["effect_script"] = PROBE_PATH
	return card


func _session(state: GameState) -> Dictionary:
	var s := States.make_session(state)
	var probe := DiscardProbe.new()
	(s["effect_handler"] as EffectHandler).registry.register_for_test(PROBE_PATH, probe,
			["on_discard_from_hand", "on_hand_card_discarded", "on_discarded_for_invasion"])
	s["probe"] = probe
	var logs: Array = []
	(s["effect_handler"] as EffectHandler).log_message.connect(func(entry: Dictionary) -> void: logs.append(entry))
	s["logs"] = logs
	return s


func _ids(cards: Array) -> Array:
	return cards.map(func(c: Dictionary) -> String: return c.get("id", ""))


func _watcher_state(hand: Array) -> GameState:
	# A watcher in zone 3 (index 2); the monster sits in zone 1.
	return States.make_state({"p0": {"hand": hand, "zone_cards": {2: _probed(Cards.battle(2, 3000, "WATCHER"))}}})


func test_gain_rage_discard_fires_self_and_watchers() -> void:
	var state := _watcher_state([_probed(Cards.battle(1, 2000, "RAGE-COST"))])
	var s := _session(state)

	await s["action_handler"].execute(CardEnums.ActionType.GAIN_RAGE, {"hand_index": 0}, state)
	await (s["effect_handler"] as EffectHandler).check_timing.resolve()

	assert_array(state.players[0].hand).is_empty()
	assert_array(_ids(state.players[0].discard_pile)).is_equal(["RAGE-COST"])
	assert_array(s["probe"].fired).contains_exactly_in_any_order(["self:RAGE-COST", "watch:WATCHER<-RAGE-COST"])


func test_invasion_cost_discard_fires_invasion_self_and_watchers() -> void:
	var state := _watcher_state([_probed(Cards.battle(1, 2000, "INV-COST", [], 1))])
	var s := _session(state)

	await s["action_handler"].execute(CardEnums.ActionType.INVADE, {"hand_index": 0}, state)
	await (s["effect_handler"] as EffectHandler).check_timing.resolve()

	assert_array(state.players[0].hand).is_empty()
	assert_array(_ids(state.players[0].discard_pile)).is_equal(["INV-COST"])
	assert_array(s["probe"].fired).contains_exactly_in_any_order(
			["invasion:INV-COST", "self:INV-COST", "watch:WATCHER<-INV-COST"])


func test_effect_discard_fires_watchers_but_not_invasion_and_logs_once() -> void:
	var a := _probed(Cards.battle(1, 2000, "A"))
	var b := Cards.strategy(1, "B")
	var keep := Cards.battle(1, 2000, "KEEP")
	var state := _watcher_state([a, keep, b])
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.check_timing.run_effect(0, {"id": "SRC"}, func() -> void:
		handler.mover.discard_from_hand(0, [a, b] as Array[Dictionary], CardMover.DiscardCause.EFFECT))
	await handler.check_timing.resolve()

	assert_array(_ids(state.players[0].hand)).is_equal(["KEEP"])
	assert_array(_ids(state.players[0].discard_pile)).is_equal(["A", "B"])
	assert_array(s["probe"].fired).contains_exactly_in_any_order(
			["self:A", "watch:WATCHER<-A", "watch:WATCHER<-B"])
	assert_array(s["logs"]).contains_exactly([GameLog.effect_discarded_cards(0, "SRC", [a, b], true)])


func test_action_discards_write_no_discard_line() -> void:
	# The Gain Rage and Invade lines already name the card.
	var state := States.make_state({"p0": {"hand": [Cards.battle(1, 2000, "RAGE-COST")]}})
	var s := _session(state)

	await s["action_handler"].execute(CardEnums.ActionType.GAIN_RAGE, {"hand_index": 0}, state)

	for entry: Dictionary in s["logs"]:
		assert_str(entry.get("type", "")).is_not_equal("effect_discarded_cards")


func test_discard_hand_to_discards_through_the_operation_and_logs() -> void:
	var a := Cards.battle(1, 2000, "A")
	var b := Cards.battle(1, 2000, "B")
	var state := _watcher_state([a, b])
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	var out: Array = []
	await handler.check_timing.run_effect(0, {"id": "SRC"}, func() -> void:
		out.append_array(await handler.discard_hand_to(0, 0)))
	await handler.check_timing.resolve()

	assert_array(_ids(out)).contains_exactly_in_any_order(["A", "B"])
	assert_array(state.players[0].hand).is_empty()
	assert_array(s["probe"].fired).contains_exactly_in_any_order(["watch:WATCHER<-A", "watch:WATCHER<-B"])
	assert_int(s["logs"].size()).is_equal(1)
	assert_str(s["logs"][0].get("type", "")).is_equal("effect_discarded_cards")


func test_select_hand_card_discards_through_the_operation_and_logs() -> void:
	var a := Cards.battle(1, 2000, "A")
	var state := _watcher_state([a])
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.check_timing.run_effect(0, {"id": "SRC"}, func() -> void:
		await handler.select_hand_card(0, func(_c: Dictionary) -> bool: return true, "pick"))
	await handler.check_timing.resolve()

	assert_array(_ids(state.players[0].discard_pile)).is_equal(["A"])
	assert_array(s["probe"].fired).contains_exactly(["watch:WATCHER<-A"])
	assert_array(s["logs"]).contains_exactly([GameLog.effect_discarded_cards(0, "SRC", [a], true)])


func test_discard_cards_logs_one_line() -> void:
	# #9: deck-reveal discards (EFC01-005 etc.) are public and logged.
	var a := Cards.battle(1, 2000, "A")
	var b := Cards.battle(1, 2000, "B")
	var state := States.make_state()
	var s := _session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.check_timing.run_effect(0, {"id": "SRC"}, func() -> void:
		handler.discard_cards(0, [a, b] as Array[Dictionary]))

	assert_array(_ids(state.players[0].discard_pile)).is_equal(["A", "B"])
	assert_array(s["logs"]).contains_exactly([GameLog.effect_discarded_cards(0, "SRC", [a, b], false)])


func test_discard_cards_empty_is_silent() -> void:
	var state := States.make_state()
	var s := _session(state)

	(s["effect_handler"] as EffectHandler).discard_cards(0, [] as Array[Dictionary])

	assert_array(s["logs"]).is_empty()


func test_discard_line_renders() -> void:
	var from_hand := GameLog.render_plain(GameLog.effect_discarded_cards(0, "SRC", [Cards.battle(1, 2000, "A")], true))
	var to_pile := GameLog.render_plain(GameLog.effect_discarded_cards(0, "SRC", [Cards.battle(1, 2000, "A")], false))
	assert_str(from_hand).is_not_empty()
	assert_str(from_hand).is_not_equal(to_pile)
	assert_str(from_hand).not_contains("STR_LOG")
	assert_str(to_pile).not_contains("STR_LOG")
