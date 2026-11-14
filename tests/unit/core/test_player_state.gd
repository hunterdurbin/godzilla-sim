extends GdUnitTestSuite

## Characterization tests for PlayerState zone/deck helpers.
## Avoids push_pending_rage_markers (depends on the CardData autoload,
## which is unavailable under the gdUnit CLI main loop).

const Cards := preload("res://tests/fixtures/cards.gd")


func test_is_zone_empty_special_cases_monster_zone() -> void:
	var player := PlayerState.new(0)
	player.monster_zone = 3
	assert_bool(player.is_zone_empty(0)).is_true()
	# The monster's own zone is never "empty" for placement purposes.
	assert_bool(player.is_zone_empty(2)).is_false()
	assert_bool(player.zone_has_battle_card(2)).is_false()


func test_battle_card_zone_indices_exclude_bare_monster_zone() -> void:
	var player := PlayerState.new(0)
	player.monster_zone = 2
	player.push_zone_card(4, Cards.battle(1))
	assert_array(player.get_battle_card_zone_indices()).contains_exactly([4])
	assert_array(player.get_empty_zone_indices()).contains_exactly([0, 2, 3, 5, 6, 7])


func test_zone_stack_push_and_top() -> void:
	var player := PlayerState.new(0)
	var bottom := Cards.battle(1, 5000, "BOTTOM")
	var top := Cards.battle(1, 5000, "TOP")
	player.push_zone_card(0, bottom)
	player.push_zone_card(0, top)
	assert_str(player.get_zone_top_card(0).get("id", "")).is_equal("TOP")
	var cleared: Array = player.clear_zone(0)
	assert_int(cleared.size()).is_equal(2)
	assert_bool(player.zone_has_cards(0)).is_false()


func test_threat_level_adds_rage() -> void:
	var player := PlayerState.new(0)
	player.current_monster = Cards.monster(1, 6000)
	player.rage = 2
	assert_int(player.get_threat_level()).is_equal(16000)


func test_total_counter_power_sums_zone_tops() -> void:
	var player := PlayerState.new(0)
	player.push_zone_card(0, Cards.battle(1, 5000, "A"))
	player.push_zone_card(0, Cards.battle(1, 3000, "A-TOP"))  # only top counts
	player.push_zone_card(5, Cards.battle(1, 4000, "B"))
	assert_int(player.get_total_counter_power()).is_equal(7000)


func test_draw_cards_moves_from_deck_to_hand() -> void:
	var player := PlayerState.new(0)
	player.main_deck.append_array([Cards.battle(1, 5000, "A"), Cards.battle(1, 5000, "B"), Cards.battle(1, 5000, "C")])
	var drawn := player.draw_cards(2)
	assert_int(drawn.size()).is_equal(2)
	assert_int(player.hand.size()).is_equal(2)
	assert_int(player.main_deck.size()).is_equal(1)


func test_draw_reshuffles_discard_when_deck_empty() -> void:
	var player := PlayerState.new(0)
	player.discard_pile.append_array([Cards.battle(1, 5000, "A"), Cards.battle(1, 5000, "B")])
	var drawn := player.draw_cards(1)
	assert_int(drawn.size()).is_equal(1)
	assert_int(player.discard_pile.size()).is_equal(0)
	assert_int(player.main_deck.size()).is_equal(1)


func test_reshuffle_filters_tokens_and_rage_cards() -> void:
	var player := PlayerState.new(0)
	var token := Cards.battle(1, 0, "TOKEN-1", [CardEnums.CardTrait.TOKEN])
	var rage_card := {"id": "RAGE-MARKER", "card_type": CardEnums.CardType.RAGE}
	player.discard_pile.append_array([Cards.battle(1, 5000, "A"), token, rage_card])
	player.draw_cards(3)
	assert_int(player.hand.size()).is_equal(1)
	assert_str(player.hand[0].get("id", "")).is_equal("A")


func test_draw_up_to_only_fills_missing() -> void:
	var player := PlayerState.new(0)
	player.hand.append_array([Cards.battle(1), Cards.battle(1), Cards.battle(1)])
	player.main_deck.append_array([Cards.battle(1, 5000, "D1"), Cards.battle(1, 5000, "D2"), Cards.battle(1, 5000, "D3")])
	player.draw_up_to(5)
	assert_int(player.hand.size()).is_equal(5)
	assert_int(player.main_deck.size()).is_equal(1)


func test_mill_cards_sends_top_to_discard() -> void:
	var player := PlayerState.new(0)
	player.main_deck.append_array([Cards.battle(1, 5000, "A"), Cards.battle(1, 5000, "B")])
	var milled := player.mill_cards(5)
	assert_int(milled.size()).is_equal(2)
	assert_int(player.discard_pile.size()).is_equal(2)
	assert_bool(player.main_deck.is_empty()).is_true()


func test_strategy_zone_helpers() -> void:
	var player := PlayerState.new(0)
	assert_bool(player.has_empty_strategy_zone()).is_true()
	assert_int(player.get_first_empty_strategy_zone_index()).is_equal(0)
	player.strategy_zones[0] = Cards.strategy(1)
	assert_int(player.get_first_empty_strategy_zone_index()).is_equal(1)
	assert_int(player.count_strategies_in_play()).is_equal(1)
	player.strategy_zones[1] = Cards.strategy(1)
	assert_bool(player.has_empty_strategy_zone()).is_false()
	assert_int(player.get_first_empty_strategy_zone_index()).is_equal(-1)


func test_strategy_zone_helpers_follow_expanded_zones() -> void:
	# EBP03-013 grows strategy_zones to 3: the first-empty lookup must reach
	# the added slot (it used to hardcode 2 zones and never returned index 2).
	var player := PlayerState.new(0)
	player.strategy_zones.append({})
	player.strategy_zones[0] = Cards.strategy(1)
	player.strategy_zones[1] = Cards.strategy(1)
	assert_bool(player.has_empty_strategy_zone()).is_true()
	assert_int(player.get_first_empty_strategy_zone_index()).is_equal(2)
	player.strategy_zones[2] = Cards.strategy(1)
	assert_bool(player.has_empty_strategy_zone()).is_false()
	assert_int(player.get_first_empty_strategy_zone_index()).is_equal(-1)
	assert_int(player.count_strategies_in_play()).is_equal(3)


func test_is_token_static() -> void:
	assert_bool(PlayerState.is_token(Cards.battle(1, 0, "T", [CardEnums.CardTrait.TOKEN]))).is_true()
	assert_bool(PlayerState.is_token(Cards.battle(1))).is_false()


func test_count_zone_tokens_by_id_matches_base_id() -> void:
	# Engine-created tokens carry the plain template id; deck-analysis boards
	# stamp per-copy instance ids ("EBP02-T03_0_1") — both must count.
	var player := PlayerState.new(0)
	player.push_zone_card(0, Cards.battle(1, 0, "EBP02-T03", [CardEnums.CardTrait.TOKEN]))
	player.push_zone_card(1, Cards.battle(1, 0, "EBP02-T03_0_1", [CardEnums.CardTrait.TOKEN]))
	# A matching base id without the TOKEN trait must not count.
	player.push_zone_card(2, Cards.battle(1, 0, "EBP02-T03_0_2"))
	assert_int(player.count_zone_tokens_by_id("EBP02-T03")).is_equal(2)


# --- Mutators emit their change signal immediately (tracker #23) ---

func _count(sig: Signal) -> Array[int]:
	## A one-cell counter bumped on every emission of `sig` (any arity).
	var fired: Array[int] = [0]
	var bump := func(_a: Variant = null) -> void: fired[0] += 1
	sig.connect(bump)
	return fired


func test_zone_mutators_emit_zones_changed() -> void:
	var player := PlayerState.new(0)
	var fired := _count(player.zones_changed)
	player.push_zone_card(0, Cards.battle(1, 5000, "TOP"))
	assert_int(fired[0]).is_equal(1)
	player.add_card_under_zone(0, Cards.battle(1, 5000, "UNDER"))
	assert_int(fired[0]).is_equal(2)
	assert_str(player.get_zone_stack(0)[1].get("id", "")).is_equal("UNDER")
	var under: Array = player.remove_cards_under_top(0)
	assert_int(fired[0]).is_equal(3)
	assert_str(under[0].get("id", "")).is_equal("UNDER")
	assert_int(player.get_zone_stack(0).size()).is_equal(1)
	player.swap_zone_stacks(0, 3)
	assert_int(fired[0]).is_equal(4)
	assert_str(player.get_zone_top_card(3).get("id", "")).is_equal("TOP")
	player.move_zone_stack(3, 5)
	assert_int(fired[0]).is_equal(5)
	assert_bool(player.zone_has_cards(3)).is_false()
	assert_str(player.get_zone_top_card(5).get("id", "")).is_equal("TOP")
	player.clear_zone(5)
	assert_int(fired[0]).is_equal(6)


func test_hand_mutators_emit_hand_changed() -> void:
	var player := PlayerState.new(0)
	var fired := _count(player.hand_changed)
	var a := Cards.battle(1, 5000, "A")
	var b := Cards.battle(1, 5000, "B")
	player.add_to_hand(a)
	player.add_cards_to_hand([b, Cards.battle(1, 5000, "C")])
	assert_int(fired[0]).is_equal(2)
	assert_str(player.remove_hand_card_at(1).get("id", "")).is_equal("B")
	assert_int(fired[0]).is_equal(3)
	player.insert_into_hand(0, b)
	assert_str(player.hand[0].get("id", "")).is_equal("B")
	assert_int(fired[0]).is_equal(4)
	assert_bool(player.remove_from_hand(a)).is_true()
	assert_int(fired[0]).is_equal(5)
	# Removing a card that isn't there changes nothing and emits nothing.
	assert_bool(player.remove_from_hand(a)).is_false()
	player.add_cards_to_hand([])
	assert_int(fired[0]).is_equal(5)
	assert_int(player.hand.size()).is_equal(2)


func test_discard_mutators_emit_discard_changed() -> void:
	var player := PlayerState.new(0)
	var fired := _count(player.discard_changed)
	var a := Cards.battle(1, 5000, "A")
	player.add_to_discard(a)
	player.add_cards_to_discard([Cards.battle(1, 5000, "B"), Cards.battle(1, 5000, "C")])
	assert_int(fired[0]).is_equal(2)
	assert_str(player.remove_discard_card_at(2).get("id", "")).is_equal("C")
	assert_bool(player.remove_from_discard(a)).is_true()
	assert_bool(player.remove_from_discard(a)).is_false()
	assert_int(fired[0]).is_equal(4)
	assert_int(player.discard_pile.size()).is_equal(1)


func test_deck_mutators_emit_deck_changed() -> void:
	var player := PlayerState.new(0)
	var fired := _count(player.deck_changed)
	player.set_main_deck([Cards.battle(1, 5000, "A"), Cards.battle(1, 5000, "B"), Cards.battle(1, 5000, "C")])
	assert_int(fired[0]).is_equal(1)
	var top: Array[Dictionary] = player.take_deck_top_cards(2)
	assert_str(top[0].get("id", "")).is_equal("A")
	assert_int(fired[0]).is_equal(2)
	# keep[0] ends up on top.
	player.put_cards_on_deck_top(top)
	assert_str(player.main_deck[0].get("id", "")).is_equal("A")
	assert_str(player.main_deck[1].get("id", "")).is_equal("B")
	player.put_on_deck_top(Cards.battle(1, 5000, "T"))
	player.put_on_deck_bottom(Cards.battle(1, 5000, "Z"))
	assert_str(player.main_deck[0].get("id", "")).is_equal("T")
	assert_str(player.main_deck[-1].get("id", "")).is_equal("Z")
	assert_str(player.remove_deck_card_at(0).get("id", "")).is_equal("T")
	player.put_cards_on_deck_bottom([Cards.battle(1, 5000, "Y")])
	player.shuffle_deck()
	assert_int(fired[0]).is_equal(8)
	assert_int(player.main_deck.size()).is_equal(5)
	# Taking from an empty deck emits nothing.
	player.set_main_deck([])
	assert_int(player.take_deck_top_cards(1).size()).is_equal(0)
	assert_int(fired[0]).is_equal(9)


func test_monster_mutators_emit_monster_changed() -> void:
	var player := PlayerState.new(0)
	var fired := _count(player.monster_changed)
	var r1 := Cards.monster(1, 6000)
	var r2 := Cards.monster(2, 8000)
	player.set_monster_deck([r1, r2])
	assert_bool(player.remove_from_monster_deck(r1)).is_true()
	player.set_current_monster(r1)
	player.push_under_monster(Cards.battle(1, 5000, "UNDER"))
	player.add_cards_under_monster([Cards.battle(1, 5000, "BOTTOM")])
	assert_int(fired[0]).is_equal(5)
	assert_str(player.monster_stack[0].get("id", "")).is_equal("UNDER")
	assert_str(player.monster_stack[1].get("id", "")).is_equal("BOTTOM")
	assert_str(player.pop_under_monster().get("id", "")).is_equal("UNDER")
	assert_int(fired[0]).is_equal(6)
	assert_int(player.monster_deck.size()).is_equal(1)


func test_set_rage_emits_rage_changed_with_value() -> void:
	var player := PlayerState.new(0)
	var seen: Array[int] = []
	player.rage_changed.connect(func(v: int) -> void: seen.append(v))
	player.set_rage(3)
	player.set_rage(1)
	assert_array(seen).contains_exactly([3, 1])
	assert_int(player.rage).is_equal(1)


func test_strategy_mutators_emit_strategy_zones_changed() -> void:
	var player := PlayerState.new(0)
	var fired := _count(player.strategy_zones_changed)
	var strat := Cards.strategy(1, "S")
	player.place_strategy(1, strat, 4)
	assert_int(player.strategy_zone_turn_placed[1]).is_equal(4)
	player.add_card_under_strategy(1, Cards.battle(1, 5000, "MARK"))
	assert_int(player.strategy_zone_stacks[1].size()).is_equal(1)
	assert_str(player.clear_strategy_zone(1).get("id", "")).is_equal("S")
	assert_bool(player.strategy_zones[1].is_empty()).is_true()
	assert_int(player.strategy_zone_stacks[1].size()).is_equal(0)
	assert_int(fired[0]).is_equal(3)


func test_set_monster_zone_emits_monster_changed() -> void:
	var player := PlayerState.new(0)
	var fired := _count(player.monster_changed)
	player.set_monster_zone(4)
	assert_int(player.monster_zone).is_equal(4)
	assert_int(fired[0]).is_equal(1)
