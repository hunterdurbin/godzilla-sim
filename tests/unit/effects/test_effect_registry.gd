extends GdUnitTestSuite

## EffectRegistry: loading, caching, trigger map lookup, test injection.

const Cards := preload("res://tests/fixtures/cards.gd")


func test_no_effect_script_returns_null() -> void:
	var registry := EffectRegistry.new()
	assert_object(registry.get_effect(Cards.battle(1))).is_null()
	assert_bool(registry.has_trigger(Cards.battle(1), "on_enter")).is_false()
	assert_bool(registry.get_trigger_filter(Cards.battle(1), "on_enter").is_empty()).is_true()


func test_real_effect_script_loads_and_caches() -> void:
	var registry := EffectRegistry.new()
	var card := Cards.monster(2)
	card["effect_script"] = "res://scripts/effects/esd01/esd01_002.gd"
	var effect := registry.get_effect(card)
	assert_object(effect).is_not_null()
	# Same instance on repeat lookups (cache hit).
	assert_bool(is_same(registry.get_effect(card), effect)).is_true()


func test_has_trigger_uses_trigger_map() -> void:
	var registry := EffectRegistry.new()
	var card := Cards.monster(2)
	card["effect_script"] = "res://scripts/effects/esd01/esd01_002.gd"
	# ESD01-002 searches the deck when invading.
	assert_bool(registry.has_trigger(card, "on_when_invading")).is_true()
	assert_bool(registry.has_trigger(card, "on_revenge")).is_false()


func test_register_for_test_injects_synthetic_effect() -> void:
	var registry := EffectRegistry.new()
	var fake := CardEffect.new()
	registry.register_for_test("test://fake_effect", fake,
		["on_enter"], {"on_enter": {"played_from_hand": true}})
	var card := Cards.battle(1)
	card["effect_script"] = "test://fake_effect"
	assert_bool(is_same(registry.get_effect(card), fake)).is_true()
	assert_bool(registry.has_trigger(card, "on_enter")).is_true()
	assert_bool(registry.has_trigger(card, "on_crush")).is_false()
	assert_bool(registry.get_trigger_filter(card, "on_enter")["played_from_hand"]).is_true()
