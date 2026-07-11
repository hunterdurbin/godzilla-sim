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
