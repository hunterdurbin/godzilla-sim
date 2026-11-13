extends GdUnitTestSuite

## Check timing (rule 10.4.3): automatic abilities triggered while an effect
## is resolving enter standby (10.6.2) and resolve only after that effect
## finishes. Replacement effects (10.2.1.3) still interrupt immediately.
## Synthetic "rest of the effect" = a choose_option prompt after the trigger.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")

const DESTROY_THEN_CHOOSE := "test://destroy_one_then_choose"
const DISCARD_THEN_CHOOSE := "test://discard_one_then_choose"


## <Enter> <Destroy> 1 of your battle cards (single-target path), then
## continue the effect with a choice. Records whether zone 8 was occupied
## when the rest of the effect ran.
class DestroyOneThenChoose:
	extends CardEffect
	var zone8_occupied_at_rest: bool = false

	func on_enter(ctx: EffectContext) -> void:
		var zones: Array[int] = ctx.owner.get_battle_card_zone_indices()
		await ctx.effect_handler.destroy_chosen_zone(ctx.owner.player_id, ctx.owner, zones, "destroy")
		zone8_occupied_at_rest = ctx.owner.zone_has_cards(7)
		await ctx.effect_handler.select_choice(ctx.owner.player_id, ["A", "B"] as Array[String], "rest")


## <Enter> Discard 1 card from your hand, then continue with a choice.
class DiscardOneThenChoose:
	extends CardEffect

	func on_enter(ctx: EffectContext) -> void:
		await ctx.effect_handler.select_hand_card(ctx.owner.player_id,
			func(_c: Dictionary) -> bool: return true, "discard")
		await ctx.effect_handler.select_choice(ctx.owner.player_id, ["A", "B"] as Array[String], "rest")


func _session(state: GameState, answers: Dictionary) -> Dictionary:
	var input := ScriptedPlayerInput.new()
	input.answers = answers
	var s := States.make_session(state, input)
	s["input"] = input
	return s


func _source(script_path: String) -> Dictionary:
	var card := Cards.strategy(1, "SOURCE")
	card["effect_script"] = script_path
	return card


func _kinds(input: ScriptedPlayerInput) -> Array:
	return input.calls.map(func(c: Dictionary) -> String: return c["kind"])


func test_single_destroy_revenge_waits_for_rest_of_effect() -> void:
	var revenge_card := Real.instance("EBP02-058")  # Revenge: search discard for a KG monster
	var state := States.make_state({"p0": {"zone_cards": {1: revenge_card}}})
	state.players[0].discard_pile.append(
		Cards.monster(3, 19000, [CardEnums.CardTrait.KING_GHIDORAH], "KG-MON"))
	var s := _session(state, {"select_zone": [1], "choose_option": [0]})
	var handler: EffectHandler = s["effect_handler"]
	handler.registry.register_for_test(DESTROY_THEN_CHOOSE, DestroyOneThenChoose.new(), ["on_enter"])

	await handler.trigger_enter(0, _source(DESTROY_THEN_CHOOSE))

	var kinds := _kinds(s["input"])
	assert_bool(kinds.has("search_cards")).is_true()
	assert_int(kinds.find("choose_option")).is_less(kinds.find("search_cards"))


func test_single_destroy_revenge_resolves_at_once_outside_an_effect() -> void:
	var revenge_card := Real.instance("EBP02-058")
	var state := States.make_state({"p0": {"zone_cards": {1: revenge_card}}})
	state.players[0].discard_pile.append(
		Cards.monster(3, 19000, [CardEnums.CardTrait.KING_GHIDORAH], "KG-MON"))
	var s := _session(state, {"select_zone": [1]})
	var handler: EffectHandler = s["effect_handler"]

	await handler.destroy_chosen_zone(0, state.players[0], [1] as Array[int], "destroy")

	assert_int(s["input"].count_calls("search_cards")).is_equal(1)


func test_discard_from_hand_ability_waits_for_rest_of_effect() -> void:
	var monster_x := Real.instance("EBP03-067")  # own turn + 2 colors → play this card
	var green := Cards.battle(2, 2000, "GREEN")
	green["colors"] = [CardEnums.CardColor.GREEN]
	var state := States.make_state({"current_player_id": 0, "p0": {
		"hand": [monster_x],
		"zone_cards": {0: Cards.battle(1, 1000, "RED"), 1: green},
	}})
	var s := _session(state, {"select_hand_card": [0], "choose_option": [0], "select_zone": [4]})
	var handler: EffectHandler = s["effect_handler"]
	handler.registry.register_for_test(DISCARD_THEN_CHOOSE, DiscardOneThenChoose.new(), ["on_enter"])

	await handler.trigger_enter(0, _source(DISCARD_THEN_CHOOSE))

	var kinds := _kinds(s["input"])
	assert_int(kinds.find("choose_option")).is_less(kinds.find("select_zone"))
	assert_str(str(state.players[0].get_zone_top_card(4).get("id"))).is_equal(str(monster_x["id"]))


func test_godzilla_earth_link_waits_for_rest_of_effect() -> void:
	var earth := Real.instance("EBP04-067")
	var token := Real.instance("EBP04-T01")
	var state := States.make_state({"p0": {"zone_cards": {7: earth, 2: token}}})
	var s := _session(state, {"select_zone": [2], "choose_option": [0]})
	var handler: EffectHandler = s["effect_handler"]
	var effect := DestroyOneThenChoose.new()
	handler.registry.register_for_test(DESTROY_THEN_CHOOSE, effect, ["on_enter"])

	await handler.trigger_enter(0, _source(DESTROY_THEN_CHOOSE))

	# Godzilla Earth was still on the field while the effect continued…
	assert_bool(effect.zone8_occupied_at_rest).is_true()
	# …and the link destroyed it at the check timing afterwards.
	assert_bool(state.players[0].zone_has_cards(7)).is_false()
	assert_str(str(state.players[0].discard_pile.back().get("id"))).is_equal(str(earth["id"]))


func test_replacement_effect_still_interrupts_mid_effect() -> void:
	var replacer := Real.instance("ESD01-011")  # "place on the bottom of your deck instead"
	var state := States.make_state({"p0": {"zone_cards": {3: replacer}}})
	var s := _session(state, {"select_zone": [3], "choose_option": [0]})
	var handler: EffectHandler = s["effect_handler"]
	handler.registry.register_for_test(DESTROY_THEN_CHOOSE, DestroyOneThenChoose.new(), ["on_enter"])

	await handler.trigger_enter(0, _source(DESTROY_THEN_CHOOSE))

	assert_bool(state.players[0].zone_has_cards(3)).is_false()
	assert_str(str(state.players[0].main_deck.back().get("id"))).is_equal(str(replacer["id"]))
	assert_int(state.players[0].discard_pile.size()).is_equal(0)
