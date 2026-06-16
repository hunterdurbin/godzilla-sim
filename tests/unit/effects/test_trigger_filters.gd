extends GdUnitTestSuite

## Table-driven tests over the declarative TRIGGER_FILTERS DSL.

const Cards := preload("res://tests/fixtures/cards.gd")


func test_empty_filter_always_passes() -> void:
	assert_bool(TriggerFilters.passes_basic({}, CardEnums.GamePhase.MAIN, true, 0, 1)).is_true()
	assert_bool(TriggerFilters.passes_enter({}, true)).is_true()
	assert_bool(TriggerFilters.passes_phase({}, CardEnums.GamePhase.END, false)).is_true()
	assert_bool(TriggerFilters.passes_own_turn({}, false)).is_true()
	assert_bool(TriggerFilters.passes_destruction_gate({}, false, -1, 0)).is_true()
	assert_bool(TriggerFilters.passes_zone_destroyed({}, 0, 3, false)).is_true()


func test_basic_phase_and_own_turn() -> void:
	var filter := {"phase": CardEnums.GamePhase.MAIN, "own_turn": true}
	assert_bool(TriggerFilters.passes_basic(filter, CardEnums.GamePhase.MAIN, true, 0, 0)).is_true()
	assert_bool(TriggerFilters.passes_basic(filter, CardEnums.GamePhase.END, true, 0, 0)).is_false()
	assert_bool(TriggerFilters.passes_basic(filter, CardEnums.GamePhase.MAIN, false, 0, 0)).is_false()


func test_basic_direction() -> void:
	assert_bool(TriggerFilters.passes_basic({"direction": "increase"}, CardEnums.GamePhase.MAIN, true, 1, 2)).is_true()
	assert_bool(TriggerFilters.passes_basic({"direction": "increase"}, CardEnums.GamePhase.MAIN, true, 2, 1)).is_false()
	assert_bool(TriggerFilters.passes_basic({"direction": "increase"}, CardEnums.GamePhase.MAIN, true, 2, 2)).is_false()
	assert_bool(TriggerFilters.passes_basic({"direction": "decrease"}, CardEnums.GamePhase.MAIN, true, 2, 1)).is_true()
	assert_bool(TriggerFilters.passes_basic({"direction": "decrease"}, CardEnums.GamePhase.MAIN, true, 1, 2)).is_false()
	# Unknown direction passes through.
	assert_bool(TriggerFilters.passes_basic({"direction": "both"}, CardEnums.GamePhase.MAIN, true, 2, 1)).is_true()


func test_enter_played_from_hand() -> void:
	assert_bool(TriggerFilters.passes_enter({"played_from_hand": true}, false)).is_true()
	assert_bool(TriggerFilters.passes_enter({"played_from_hand": true}, true)).is_false()
	assert_bool(TriggerFilters.passes_enter({"played_from_hand": false}, true)).is_true()
	assert_bool(TriggerFilters.passes_enter({"played_from_hand": false}, false)).is_false()


func test_cause_gate_matrix() -> void:
	# Watcher is player 0. caused_by_opponent: true.
	var by_opp := {"caused_by_opponent": true}
	assert_bool(TriggerFilters.passes_cause_gate(by_opp, 1, 0)).is_true()   # opponent's effect
	assert_bool(TriggerFilters.passes_cause_gate(by_opp, 0, 0)).is_false()  # own effect
	assert_bool(TriggerFilters.passes_cause_gate(by_opp, -1, 0)).is_false() # rules-based: matches neither
	# caused_by_opponent: false (= own effect only).
	var by_self := {"caused_by_opponent": false}
	assert_bool(TriggerFilters.passes_cause_gate(by_self, 0, 0)).is_true()
	assert_bool(TriggerFilters.passes_cause_gate(by_self, 1, 0)).is_false()
	assert_bool(TriggerFilters.passes_cause_gate(by_self, -1, 0)).is_false()


func test_discard_from_hand_combines_cause_and_turn() -> void:
	var filter := {"caused_by_opponent": true, "own_turn": false}
	assert_bool(TriggerFilters.passes_discard_from_hand(filter, false, 1, 0)).is_true()
	assert_bool(TriggerFilters.passes_discard_from_hand(filter, true, 1, 0)).is_false()
	assert_bool(TriggerFilters.passes_discard_from_hand(filter, false, 0, 0)).is_false()


func test_battle_card_played_keys() -> void:
	var filter := {"played_by_opponent": true, "played_from_deck": true}
	assert_bool(TriggerFilters.passes_battle_card_played(filter, true, true, true)).is_true()
	assert_bool(TriggerFilters.passes_battle_card_played(filter, true, false, true)).is_false()
	assert_bool(TriggerFilters.passes_battle_card_played(filter, true, true, false)).is_false()
	assert_bool(TriggerFilters.passes_battle_card_played({"own_turn": false}, true, true, true)).is_false()


func test_hand_discarded_card_type() -> void:
	var battle := Cards.battle(1)
	var strategy := Cards.strategy(1)
	var monster := Cards.monster(1)
	assert_bool(TriggerFilters.passes_hand_discarded({"card_type": "battle"}, true, battle)).is_true()
	assert_bool(TriggerFilters.passes_hand_discarded({"card_type": "battle"}, true, strategy)).is_false()
	assert_bool(TriggerFilters.passes_hand_discarded({"card_type": "strategy"}, true, strategy)).is_true()
	assert_bool(TriggerFilters.passes_hand_discarded({"card_type": "monster"}, true, monster)).is_true()
	assert_bool(TriggerFilters.passes_hand_discarded({"card_type": "monster", "own_turn": true}, false, monster)).is_false()


func test_strategy_hand_rank_modifier_keys() -> void:
	var filter := {"target_is_owner": true}
	assert_bool(TriggerFilters.passes_strategy_hand_rank_modifier(filter, true, true)).is_true()
	assert_bool(TriggerFilters.passes_strategy_hand_rank_modifier(filter, true, false)).is_false()


func test_card_returned_keys() -> void:
	var filter := {"returned_by_opponent": true}
	assert_bool(TriggerFilters.passes_card_returned(filter, true, true)).is_true()
	assert_bool(TriggerFilters.passes_card_returned(filter, true, false)).is_false()


func test_zone_destroyed_monster_column() -> void:
	# Watcher monster at zone 3 (anchor index 2). Same-side column zones.
	var same_side: Array[int] = CardEffect.get_column_zones(2)
	var cross: Array[int] = CardEffect.get_opponent_column_zones(2)
	var filter := {"column": "monster"}
	for zi in range(8):
		assert_bool(TriggerFilters.passes_zone_destroyed(filter, 3, zi, false)).is_equal(zi in same_side)
		assert_bool(TriggerFilters.passes_zone_destroyed(filter, 3, zi, true)).is_equal(zi in cross)
	# No anchor (monster_zone <= 0) -> fail.
	assert_bool(TriggerFilters.passes_zone_destroyed(filter, 0, 2, false)).is_false()


func test_prevents_monster_move_combines_gates() -> void:
	var filter := {"caused_by_opponent": true}
	assert_bool(TriggerFilters.passes_prevents_monster_move(filter, true, 1, 0)).is_true()
	assert_bool(TriggerFilters.passes_prevents_monster_move(filter, true, -1, 0)).is_false()
	assert_bool(TriggerFilters.passes_prevents_monster_move({"own_turn": true}, false, -1, 0)).is_false()
