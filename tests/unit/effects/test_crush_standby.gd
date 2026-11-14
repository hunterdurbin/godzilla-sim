extends GdUnitTestSuite

## Crush (11.3) is an interrupt rule action, but the abilities it triggers
## (leave-play, crush, <Revenge>) are automatic abilities: they enter standby
## (10.6.2) and resolve at the check timing as one pool (10.4.3.1–10.4.3.4).
## After every ability: rule actions, then the turn player picks one of ALL
## their standby abilities, else the non-turn player picks one of theirs.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")

const REVENGE := "test://record_revenge"
const LEAVE_AND_REVENGE := "test://record_leave_and_revenge"


## <Revenge>: log "revenge:<id>" plus a snapshot of how many battle cards
## are still in either player's monster zone (0 once every crush is done).
class RecordRevenge:
	extends CardEffect
	var seen: Array = []
	var state: GameState

	func on_revenge(ctx: EffectContext) -> void:
		var uncrushed := 0
		for p in state.players:
			if p.zone_has_cards(p.monster_zone - 1):
				uncrushed += 1
		seen.append("revenge:%s:uncrushed=%d" % [ctx.card_data.get("id"), uncrushed])


## A card with both a leave-play and a <Revenge> ability.
class RecordLeaveAndRevenge:
	extends CardEffect
	var seen: Array = []

	func on_leave_play(_ctx: EffectContext, _zone_index: int) -> void:
		seen.append("leave")

	func on_revenge(_ctx: EffectContext) -> void:
		seen.append("revenge")


func _session(state: GameState, answers: Dictionary = {}) -> Dictionary:
	var input := ScriptedPlayerInput.new()
	input.answers = answers
	var s := States.make_session(state, input)
	s["input"] = input
	return s


func _card(id: String, script_path: String) -> Dictionary:
	var c := Cards.battle(1, 5000, id)
	c["effect_script"] = script_path
	return c


## Option count of each standby order prompt, in order.
func _prompt_sizes(input: ScriptedPlayerInput) -> Array:
	return input.calls_of("choose_option") \
		.map(func(c: Dictionary) -> int: return c["options"].size())


func _entry(player_id: int, card: Dictionary, callback: Callable) -> StandbyEntry:
	return StandbyEntry.new(player_id, card, callback)


# --- Crush rule action → standby ---

func test_both_players_crushed_revenge_resolves_in_standby_turn_player_first() -> void:
	var state := States.make_state({"allow_illegal": true, 
		"current_player_id": 1,
		"p0": {"monster_zone": 2, "zone_cards": {1: _card("P0-REV", REVENGE)}},
		"p1": {"monster_zone": 5, "zone_cards": {4: _card("P1-REV", REVENGE)}},
	})
	var s := _session(state)
	var effect := RecordRevenge.new()
	effect.state = state
	s["effect_handler"].registry.register_for_test(REVENGE, effect, ["on_revenge"])

	await (s["effect_handler"] as EffectHandler).check_timing.resolve()

	# Both crushes happen first (rule actions, 10.4.3.1); only then do the
	# Revenge abilities resolve from standby, turn player (1) first.
	assert_array(effect.seen).contains_exactly([
		"revenge:P1-REV:uncrushed=0",
		"revenge:P0-REV:uncrushed=0",
	])


func test_crushed_card_leave_play_and_revenge_share_one_order_prompt() -> void:
	var state := States.make_state({"allow_illegal": true, "p0": {
		"monster_zone": 3,
		"zone_cards": {2: _card("BOTH", LEAVE_AND_REVENGE)},
	}})
	var s := _session(state, {"choose_option": [1]})
	var effect := RecordLeaveAndRevenge.new()
	s["effect_handler"].registry.register_for_test(LEAVE_AND_REVENGE, effect, ["on_leave_play", "on_revenge"])

	await (s["effect_handler"] as EffectHandler).check_timing.resolve()

	assert_array(_prompt_sizes(s["input"])).contains_exactly([2])
	# The player picked the second listed ability (Revenge) first.
	assert_array(effect.seen).contains_exactly(["revenge", "leave"])


# --- Standby is one pool, re-evaluated after every ability ---

func test_turn_player_crush_preempts_non_turn_players_remaining_abilities() -> void:
	# P0 is the turn player; P1 has two abilities in standby. P1's first one
	# moves P0's monster onto a P0 Revenge card: after it resolves, the check
	# timing crushes that card and P0's Revenge (turn player) goes next —
	# before P1's remaining ability (10.4.3.1 → 10.4.3.2).
	var state := States.make_state({
		"current_player_id": 0,
		"p0": {"monster_zone": 1, "zone_cards": {3: _card("P0-REV", REVENGE)}},
	})
	var s := _session(state, {"choose_option": [0]})
	var handler: EffectHandler = s["effect_handler"]
	var effect := RecordRevenge.new()
	effect.state = state
	handler.registry.register_for_test(REVENGE, effect, ["on_revenge"])
	var crusher := func() -> void:
		effect.seen.append("p1:crusher")
		state.players[0].monster_zone = 4
	var other := func() -> void: effect.seen.append("p1:other")

	handler.check_timing.submit([
		_entry(1, Cards.battle(1, 5000, "P1-A"), crusher),
		_entry(1, Cards.battle(1, 5000, "P1-B"), other),
	])
	await handler.check_timing.resolve()

	assert_array(effect.seen).contains_exactly([
		"p1:crusher",
		"revenge:P0-REV:uncrushed=0",
		"p1:other",
	])


func test_ability_added_mid_resolution_joins_same_players_next_order_prompt() -> void:
	var state := States.make_state()
	var s := _session(state, {"choose_option": [0, 1]})
	var handler: EffectHandler = s["effect_handler"]
	var order: Array = []
	var spawned := _entry(0, Cards.battle(1, 5000, "C"), func() -> void: order.append("c"))
	var spawner := func() -> void:
		order.append("a")
		# Triggered while A resolves → enters standby behind it.
		handler.check_timing.submit([spawned])

	handler.check_timing.submit([
		_entry(0, Cards.battle(1, 5000, "A"), spawner),
		_entry(0, Cards.battle(1, 5000, "B"), func() -> void: order.append("b")),
	])
	await handler.check_timing.resolve()

	# Second prompt offers B and the new C together; picking the second (C)
	# resolves it before B.
	assert_array(_prompt_sizes(s["input"])).contains_exactly([2, 2])
	assert_array(order).contains_exactly(["a", "c", "b"])


# --- EBP03-068 Godzilla Flies: zone 3 → zone 8, crush only the destination ---

func _flies_state(zone8_card: Dictionary) -> GameState:
	var state := States.make_state({"p0": {
		"monster_zone": 3,
		"current_monster": Cards.monster(3, 15000),
		"zone_cards": {4: Cards.battle(1, 5000, "Z5"), 7: zone8_card},
		"main_deck": [Cards.battle(1, 2000, "D1")],
	}})
	state.players[0].discard_pile.append(
		Cards.monster(3, 19000, [CardEnums.CardTrait.KING_GHIDORAH], "KG-MON"))
	return state


func test_godzilla_flies_crushed_zone8_revenge_enters_standby() -> void:
	var revenge_card := Real.instance("EBP02-058")  # Revenge: search discard for a KG monster
	var state := _flies_state(revenge_card)
	var s := _session(state)

	s["effect_handler"].trigger_enter(0, Real.instance("EBP03-068"))
	await s["effect_handler"].check_timing.resolve()

	var p0 := state.players[0]
	assert_int(p0.monster_zone).is_equal(8)
	assert_bool(p0.zone_has_cards(4)).override_failure_message("zones 4–7 are not crushed").is_true()
	assert_bool(p0.zone_has_cards(7)).is_false()
	assert_bool(p0.discard_pile.has(revenge_card)).is_true()
	assert_bool(p0.cards_destroyed_this_turn.has(revenge_card)).is_true()
	assert_int(s["input"].count_calls("search_cards")).is_equal(1)


func test_godzilla_flies_crushed_godzilla_2023_goes_to_deck_bottom() -> void:
	var replacer := Real.instance("ESD01-011")  # "place on the bottom of your deck instead"
	var state := _flies_state(replacer)
	var s := _session(state)

	s["effect_handler"].trigger_enter(0, Real.instance("EBP03-068"))
	await s["effect_handler"].check_timing.resolve()

	var p0 := state.players[0]
	assert_int(p0.monster_zone).is_equal(8)
	assert_bool(p0.zone_has_cards(7)).is_false()
	assert_bool(p0.discard_pile.has(replacer)).is_false()
	assert_array(p0.main_deck).is_not_empty()
	assert_str(str(p0.main_deck.back().get("id"))).is_equal(str(replacer["id"]))
	assert_int(p0.cards_destroyed_this_turn.size()).is_equal(0)


# --- EBP04-078 The Slithering Disaster: teleport_monster crushes the destination ---

func test_teleport_onto_revenge_card_crushes_it_and_revenge_enters_standby() -> void:
	# P0's effect moves P1's monster from zone 3 straight to zone 8, where a
	# P1 Revenge card sits: the crush happens as part of the move (interrupt
	# rule action, 11.1.2.1) — no check timing runs in this test — and the
	# Revenge resolves from standby.
	var state := States.make_state({"p1": {
		"monster_zone": 3,
		"zone_cards": {7: _card("P1-REV", REVENGE)},
	}})
	var s := _session(state)
	var effect := RecordRevenge.new()
	effect.state = state
	s["effect_handler"].registry.register_for_test(REVENGE, effect, ["on_revenge"])
	var card := Real.instance("EBP04-078")
	state.players[0].strategy_zones[0] = card

	s["effect_handler"].trigger_enter(0, card)
	await s["effect_handler"].check_timing.resolve()

	var p1 := state.players[1]
	assert_int(p1.monster_zone).is_equal(8)
	assert_bool(p1.zone_has_cards(7)).is_false()
	assert_int(p1.cards_destroyed_this_turn.size()).is_equal(1)
	assert_array(effect.seen).contains_exactly(["revenge:P1-REV:uncrushed=0"])
