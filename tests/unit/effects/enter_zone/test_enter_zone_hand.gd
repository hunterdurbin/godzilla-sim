extends GdUnitTestSuite

## EnterZone, hand source: the main-phase Play action (by_effect = false)
## and an effect playing a battle card from the hand (by_effect = true).
## Rule legality (5.11.1.1 monster zone, EBP02-055 opponent block, the
## card's required zones) is asked of the operation; cost legality (rank)
## stays in RulesEngine. An effect play refuses the monster's zone and the
## opponent's block like the Play action, and stacks a stack-on-play card;
## only the Play action applies the card's required zones.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")

const Source := EnterZone.Source

const MONSTER_ZONE_IDX := 3  # p0's monster in zone 4
const ZONE := 5
const BLOCKER := "test://enter_zone_blocker"
const REQUIRES := "test://enter_zone_requires"
const STACKER := "test://enter_zone_stacker"
const ENTER := "test://enter_zone_enter"
const WATCHER := "test://enter_zone_played_watcher"
const LEAVE := "test://enter_zone_leave"


## Opponent card: p0 can't place cards in zone ZONE (EBP02-055 style).
class BlockZone:
	extends CardEffect

	func get_blocked_opponent_zones(_ctx: EffectContext) -> Array[int]:
		return [ZONE]


## A card that may only be played into zone 1.
class RequireZoneOne:
	extends CardEffect

	func get_required_play_zones(_ctx: EffectContext) -> Array[int]:
		return [0]


## Godzilla Jr. style: stacks on top of an occupied zone when played.
class StackOnPlay:
	extends CardEffect

	func stacks_on_play(_ctx: EffectContext, _zone_index: int) -> bool:
		return true


class RecordEnter:
	extends CardEffect
	var seen: Array = []

	func on_enter(ctx: EffectContext) -> void:
		seen.append("enter:%s:effect=%s" % [ctx.card_data.get("id"),
				ctx.card_data.get("played_from_effect", false)])


class RecordPlayed:
	extends CardEffect
	var seen: Array = []

	func on_battle_card_played(_ctx: EffectContext, zone_index: int, from_deck: bool = false) -> void:
		seen.append("played:%d:deck=%s" % [zone_index, from_deck])


class RecordLeave:
	extends CardEffect
	var seen: Array = []

	func on_leave_play(ctx: EffectContext, zone_index: int) -> void:
		seen.append("leave:%s:%d" % [ctx.card_data.get("id"), zone_index])


func _card(id: String, script_path: String = "") -> Dictionary:
	var c := Cards.battle(1, 5000, id)
	if script_path != "":
		c["effect_script"] = script_path
	return c


func _setup(p0: Dictionary = {}, p1: Dictionary = {}) -> Dictionary:
	var p0_opts: Dictionary = {"monster_zone": MONSTER_ZONE_IDX + 1}
	p0_opts.merge(p0)
	var state := States.make_state({"p0": p0_opts, "p1": p1})
	var s := States.make_session(state)
	s["state"] = state
	return s


func _teardown(s: Dictionary) -> void:
	var ah: ActionHandler = s["action_handler"]
	ah.teardown()
	var handler: EffectHandler = s["effect_handler"]
	handler.teardown()


func _legal(s: Dictionary, card: Dictionary, zone: int, by_effect: bool) -> bool:
	var handler: EffectHandler = s["effect_handler"]
	var state: GameState = s["state"]
	return EnterZone.is_rule_legal(handler.queries, state.players[0], state.players[1],
			card, zone, by_effect)


# --- Rule legality ---

func test_the_play_action_refuses_the_monster_zone() -> void:
	var s := _setup()
	assert_bool(_legal(s, _card("C"), MONSTER_ZONE_IDX, false)).is_false()
	assert_bool(_legal(s, _card("C"), ZONE, false)).is_true()
	_teardown(s)


func test_the_play_action_refuses_a_zone_the_opponent_blocks() -> void:
	var s := _setup({}, {"zone_cards": {2: _card("BLOCK", BLOCKER)}})
	s["effect_handler"].registry.register_for_test(BLOCKER, BlockZone.new(), ["get_blocked_opponent_zones"])
	assert_bool(_legal(s, _card("C"), ZONE, false)).is_false()
	assert_bool(_legal(s, _card("C"), ZONE + 1, false)).is_true()
	_teardown(s)


func test_the_play_action_honours_the_cards_required_zones() -> void:
	var s := _setup()
	s["effect_handler"].registry.register_for_test(REQUIRES, RequireZoneOne.new(), ["get_required_play_zones"])
	var card := _card("REQ", REQUIRES)
	assert_bool(_legal(s, card, 0, false)).is_true()
	assert_bool(_legal(s, card, ZONE, false)).is_false()
	_teardown(s)


func test_an_effect_play_refuses_the_monster_zone_and_the_opponents_block() -> void:
	var s := _setup({}, {"zone_cards": {2: _card("BLOCK", BLOCKER)}})
	s["effect_handler"].registry.register_for_test(BLOCKER, BlockZone.new(), ["get_blocked_opponent_zones"])
	assert_bool(_legal(s, _card("C"), MONSTER_ZONE_IDX, true)).is_false()
	assert_bool(_legal(s, _card("C"), ZONE, true)).is_false()
	assert_bool(_legal(s, _card("C"), ZONE + 1, true)).is_true()
	_teardown(s)


func test_an_effect_play_ignores_the_cards_required_zones() -> void:
	var s := _setup()
	s["effect_handler"].registry.register_for_test(REQUIRES, RequireZoneOne.new(), ["get_required_play_zones"])
	assert_bool(_legal(s, _card("REQ", REQUIRES), ZONE, true)).is_true()
	_teardown(s)


func test_out_of_range_zones_are_refused() -> void:
	var s := _setup()
	for by_effect: bool in [false, true]:
		assert_bool(_legal(s, _card("C"), -1, by_effect)).is_false()
		assert_bool(_legal(s, _card("C"), 8, by_effect)).is_false()
	_teardown(s)


func test_rules_engine_asks_the_operation_for_rule_legality() -> void:
	var s := _setup({}, {"zone_cards": {2: _card("BLOCK", BLOCKER)}})
	s["effect_handler"].registry.register_for_test(BLOCKER, BlockZone.new(), ["get_blocked_opponent_zones"])
	var rules: RulesEngine = s["rules"]
	var state: GameState = s["state"]
	var zones := rules.get_valid_zones_for_card(_card("C"), state.players[0], state.players[1])
	assert_array(zones).not_contains([MONSTER_ZONE_IDX, ZONE])
	assert_array(zones).contains([0, 1, 2, 4, 6, 7])
	_teardown(s)


# --- enter(): placement, Overload / stack-on-play, entries ---

## Registers the recording effects; returns them keyed by script path.
func _register(s: Dictionary) -> Dictionary:
	var handler: EffectHandler = s["effect_handler"]
	var fx := {ENTER: RecordEnter.new(), WATCHER: RecordPlayed.new(), LEAVE: RecordLeave.new()}
	handler.registry.register_for_test(ENTER, fx[ENTER], ["on_enter"])
	handler.registry.register_for_test(WATCHER, fx[WATCHER], ["on_battle_card_played"])
	handler.registry.register_for_test(LEAVE, fx[LEAVE], ["on_leave_play"])
	return fx


func _seen(fx: Dictionary) -> Array:
	var all: Array = []
	for path: String in [LEAVE, ENTER, WATCHER]:
		all.append_array(fx[path].seen)
	return all


func test_the_play_action_overloads_and_queues_leave_enter_and_played_together() -> void:
	var old := _card("OLD", LEAVE)
	var card := _card("NEW", ENTER)
	var s := _setup({"zone_cards": {ZONE: old, 0: _card("WATCH", WATCHER)}})
	var fx := _register(s)
	var handler: EffectHandler = s["effect_handler"]
	var events: GameEvents = s["events"]
	var p0: PlayerState = s["state"].players[0]
	var announced: Array = []
	events.battle_card_played.connect(func(pid: int, c: Dictionary, z: int) -> void:
		announced.append([pid, c.get("id"), z]))

	var entered: bool = handler.enter_zone.enter(0, card, ZONE, Source.HAND, false)

	assert_bool(entered).is_true()
	assert_dict(p0.get_zone_top_card(ZONE)).is_equal(card)
	assert_array(p0.zones[ZONE]).has_size(1)
	assert_bool(p0.discard_pile.has(old)).is_true()
	assert_array(announced).contains_exactly([[0, "NEW", ZONE]])
	# Nothing resolves on the spot: all three wait for the check timing.
	assert_array(_seen(fx)).is_empty()
	await handler.check_timing.resolve()
	assert_array(_seen(fx)).contains_exactly_in_any_order(
			["leave:OLD:%d" % ZONE, "enter:NEW:effect=false", "played:%d:deck=false" % ZONE])
	_teardown(s)


func test_the_play_action_stacks_a_stack_on_play_card() -> void:
	var under := _card("UNDER")
	var card := _card("JR", STACKER)
	var s := _setup({"zone_cards": {ZONE: under}})
	var handler: EffectHandler = s["effect_handler"]
	handler.registry.register_for_test(STACKER, StackOnPlay.new(), ["stacks_on_play"])
	var p0: PlayerState = s["state"].players[0]

	handler.enter_zone.enter(0, card, ZONE, Source.HAND, false)

	assert_array(p0.zones[ZONE]).contains_exactly([card, under])
	assert_bool(p0.discard_pile.has(under)).is_false()
	_teardown(s)


func test_an_effect_play_from_hand_takes_the_card_out_of_the_hand() -> void:
	var card := _card("NEW", ENTER)
	var s := _setup({"hand": [card], "zone_cards": {0: _card("WATCH", WATCHER)}})
	var fx := _register(s)
	var handler: EffectHandler = s["effect_handler"]
	var p0: PlayerState = s["state"].players[0]

	var entered: bool = handler.enter_zone.enter(0, card, ZONE, Source.HAND)
	await handler.check_timing.resolve()

	assert_bool(entered).is_true()
	assert_array(p0.hand).is_empty()
	assert_dict(p0.get_zone_top_card(ZONE)).is_equal(card)
	assert_array(_seen(fx)).contains_exactly_in_any_order(
			["enter:NEW:effect=true", "played:%d:deck=false" % ZONE])
	_teardown(s)


func test_an_effect_play_from_hand_into_the_monster_zone_is_not_played() -> void:
	var card := _card("NEW", ENTER)
	var s := _setup({"hand": [card]})
	var fx := _register(s)
	var handler: EffectHandler = s["effect_handler"]
	var p0: PlayerState = s["state"].players[0]

	var entered: bool = handler.enter_zone.enter(0, card, MONSTER_ZONE_IDX, Source.HAND)
	await handler.check_timing.resolve()

	assert_bool(entered).is_false()
	assert_array(p0.hand).contains_exactly([card])
	assert_bool(p0.zone_has_cards(MONSTER_ZONE_IDX)).is_false()
	assert_array(_seen(fx)).is_empty()
	_teardown(s)
