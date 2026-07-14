extends GdUnitTestSuite

## BotDeckProfile — deck-shape invasion-viability metric for the KAIJU
## evaluator. Pure static; tags injected so no EffectHandler is needed.


func _tags_from_meta(card: Dictionary) -> Array[String]:
	var tags: Array[String] = []
	tags.assign(card.get("_tags", []))
	return tags


func _card(tags: Array = [], icon: int = 0) -> Dictionary:
	return {"_tags": tags, "invasion_icon": icon}


func _compute(cards: Array, inv: float = 10.0, cnt: float = 10.0) -> Dictionary:
	return BotDeckProfile.compute(cards, _tags_from_meta, inv, cnt)


func test_empty_pool_returns_empty() -> void:
	assert_that(BotDeckProfile.compute([], _tags_from_meta, 1.0, 1.0)).is_equal({})


func test_no_capability_hits_viability_floor_region() -> void:
	var cards: Array = []
	for i in range(20):
		cards.append(_card([], 0))
	var profile := _compute(cards, 0.0, 20.0) # pure counter deck, no icons/destroys
	assert_float(profile["invasion_viability"]).is_less_equal(0.1)
	assert_float(profile["invasion_viability"]).is_greater_equal(BotDeckProfile.VIABILITY_FLOOR)
	assert_float(profile["clear_capability"]).is_equal(0.0)


func test_clear_capability_saturates_at_two_destroys() -> void:
	var two: Array = [_card(["destroys_zone"]), _card(["destroys_zone"]), _card()]
	var three: Array = [_card(["destroys_zone"]), _card(["destroys_zone"]), _card(["destroys_zone"])]
	assert_float(_compute(two)["clear_capability"]).is_equal(1.0)
	assert_float(_compute(three)["clear_capability"]).is_equal(1.0)
	assert_int(_compute(three)["destroy_count"]).is_equal(3)


func test_viability_monotonic_in_invade_density() -> void:
	var low: Array = []
	var high: Array = []
	for i in range(10):
		low.append(_card([], 1 if i < 2 else 0))
		high.append(_card([], 2 if i < 5 else 0))
	assert_float(_compute(high)["invasion_viability"]) \
			.is_greater(_compute(low)["invasion_viability"])
	assert_int(_compute(high)["invade2_count"]).is_equal(5)


func test_viability_clamped_to_valid_range() -> void:
	var loaded: Array = []
	for i in range(10):
		loaded.append(_card(["destroys_zone", "advances_opponent"], 2))
	var profile := _compute(loaded, 100.0, 0.0)
	assert_float(profile["invasion_viability"]).is_less_equal(1.0)
	assert_float(profile["invasion_viability"]).is_greater_equal(0.9)
