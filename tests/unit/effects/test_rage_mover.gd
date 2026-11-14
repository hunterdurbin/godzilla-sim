extends GdUnitTestSuite

## RageMover (hunterdurbin/godzilla-sim-issue-tracker#35 rows 18-21): the one
## writer for Rage. Every increase emits GameEvents.rage_gained and writes the
## log line, whatever caused it.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")


func _session(state: GameState) -> Dictionary:
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]
	if handler.events == null:
		handler.events = GameEvents.new()
	return s


func test_effect_gain_emits_rage_gained_and_logs() -> void:
	var state := States.make_state({"p0": {"rage": 1}})
	var handler: EffectHandler = _session(state)["effect_handler"]
	var emitted: Array = []
	handler.events.rage_gained.connect(func(pid: int, total: int) -> void: emitted.append([pid, total]))
	var logged: Array = []
	handler.log_message.connect(func(entry: Dictionary) -> void: logged.append(entry))

	var gained: int = handler.gain_rage(0, 2, "SRC-CARD")

	assert_int(gained).is_equal(2)
	assert_int(state.players[0].rage).is_equal(3)
	assert_array(emitted).contains_exactly([[0, 3]])
	assert_array(logged).contains_exactly([GameLog.rage_gained(0, 2, 3, "SRC-CARD")])


## Records the Rage spans its watcher resolves with, and answers
## on_rage_reset with `keep` (filters are passed at registration).
class RageProbe:
	extends CardEffect
	var spans: Array = []
	var keep: int = 0

	func on_rage_changed(_ctx: EffectContext, old_rage: int, new_rage: int) -> void:
		spans.append([old_rage, new_rage])

	func on_rage_reset(_ctx: EffectContext) -> int:
		return keep


func _probe(s: Dictionary, card: Dictionary, triggers: Array, direction: String) -> RageProbe:
	card["effect_script"] = "test://rage_probe"
	var probe := RageProbe.new()
	(s["effect_handler"] as EffectHandler).registry.register_for_test("test://rage_probe", probe, triggers,
			{"on_rage_changed": {"direction": direction}})
	return probe


func _recorders(s: Dictionary) -> Dictionary:
	var handler: EffectHandler = s["effect_handler"]
	var rec := {"events": [], "logs": []}
	handler.events.rage_gained.connect(func(pid: int, total: int) -> void: rec["events"].append([pid, total]))
	handler.log_message.connect(func(entry: Dictionary) -> void: rec["logs"].append(entry))
	return rec


func test_gain_rage_action_emits_rage_gained_and_logs() -> void:
	var state := States.make_state({"p0": {"hand": [Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "DISCARDED")]}})
	var s := _session(state)
	var rec := _recorders(s)

	await s["action_handler"].execute(CardEnums.ActionType.GAIN_RAGE, {"hand_index": 0}, state)

	assert_int(state.players[0].rage).is_equal(1)
	assert_array(rec["events"]).contains_exactly([[0, 1]])
	assert_array(rec["logs"]).contains([GameLog.gained_rage(0, 1, "DISCARDED")])


func test_monster_play_increase_emits_logs_and_reaches_the_played_monster() -> void:
	# 8.5.1.1: the +1 comes once the played card is the invading monster, so
	# its own "whenever this card's <Rage> is increased" ability sees it.
	var played := Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "NEW-M")
	var state := States.make_state({"p0": {"hand": [played]}})
	var s := _session(state)
	var probe := _probe(s, played, ["on_rage_changed"], "increase")
	var rec := _recorders(s)

	await s["action_handler"].execute(CardEnums.ActionType.PLAY_MONSTER, {"hand_index": 0}, state)
	await (s["effect_handler"] as EffectHandler).check_timing.resolve()

	assert_str(str(state.players[0].current_monster.get("id"))).is_equal("NEW-M")
	assert_int(state.players[0].rage).is_equal(1)
	assert_array(rec["events"]).contains_exactly([[0, 1]])
	assert_array(rec["logs"]).contains([GameLog.rage_gained(0, 1, 1, "NEW-M")])
	assert_array(probe.spans).contains_exactly([[0, 1]])


func test_reset_kept_value_is_a_drop_not_an_increase() -> void:
	# Q508: "if Rage is 5, it becomes 5 → 2. It does not go 5 → 0 → 2."
	var monster := Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "KEEPER")
	var state := States.make_state({"p0": {"current_monster": monster, "rage": 5}})
	var s := _session(state)
	var probe := _probe(s, monster, ["on_rage_changed", "on_rage_reset"], "decrease")
	probe.keep = 2
	var rec := _recorders(s)

	await s["action_handler"].execute_start_phase_reset(state)
	await (s["effect_handler"] as EffectHandler).check_timing.resolve()

	assert_int(state.players[0].rage).is_equal(2)
	assert_array(probe.spans).contains_exactly([[5, 2]])
	assert_array(rec["events"]).is_empty()
