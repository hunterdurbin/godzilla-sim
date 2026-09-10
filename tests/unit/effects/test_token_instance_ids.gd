extends GdUnitTestSuite

## Engine-created tokens must carry per-copy instance ids ("EBP02-T03_tok_1"),
## like deck cards get at deck build. Same-id tokens in play broke id-keyed
## zone lookups: _can_destroy_card resolved a third "Crystals" copy in zone 8
## to the first copy's zone index, so EBP01-080 (protects zones 1-5 only)
## wrongly shielded upper-zone tokens from destruction.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func test_created_tokens_get_unique_instance_ids() -> void:
	var state := States.make_state({})
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.create_token_in_zone(state.players[1], "EBP02-T03", 0)
	await handler.create_token_in_zone(state.players[1], "EBP02-T03", 2)

	var a := state.players[1].get_zone_top_card(0)
	var b := state.players[1].get_zone_top_card(2)
	assert_str(CardUtils.base_id(a)).is_equal("EBP02-T03")
	assert_str(CardUtils.base_id(b)).is_equal("EBP02-T03")
	assert_bool(a.get("id") == b.get("id")).is_false()
	assert_int(state.players[1].count_zone_tokens_by_id("EBP02-T03")).is_equal(2)


func test_zone_protection_resolves_correct_zone_for_token_copies() -> void:
	# Reported bug board: defender has EBP01-080 (protects rank <=5 in zones
	# 1-5) and Crystals tokens in zones 1, 3 and 8; attacker's monster in
	# zone 8 plays Godzilla's Bite (EPR-005) -> column [2, 7]. The zone-3
	# crystal is protected; the zone-8 crystal must be destroyed.
	var state := States.make_state({
		"p0": {"monster_zone": 8, "current_monster": Real.instance("EBP03-002"), "rage": 1},
		"p1": {"monster_zone": 7, "current_monster": Real.instance("EBP02-053")},
	})
	state.players[1].strategy_zones[0] = Real.instance("EBP01-080")
	var s := States.make_session(state)
	var handler: EffectHandler = s["effect_handler"]

	await handler.create_token_in_zone(state.players[1], "EBP02-T03", 0)
	await handler.create_token_in_zone(state.players[1], "EBP02-T03", 2)
	await handler.create_token_in_zone(state.players[1], "EBP02-T03", 7)

	handler.exec.set_active(0, {"id": "P0-FX"})
	assert_bool(handler.can_destroy_card(state.players[1], state.players[1].get_zone_top_card(0))).is_false()
	assert_bool(handler.can_destroy_card(state.players[1], state.players[1].get_zone_top_card(7))).is_true()
	handler.exec.clear_active()

	var bite := Real.instance("EPR-005")
	await handler.trigger_enter(0, bite)

	assert_bool(state.players[1].zone_has_cards(2)).is_true()    # zone 3: protected
	assert_bool(state.players[1].zone_has_cards(7)).is_false()   # zone 8: destroyed
