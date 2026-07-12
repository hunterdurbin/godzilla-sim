extends GdUnitTestSuite

## KaijuCounterOracle: the bot's bridge to the deck-analysis optimizer —
## "max CP still fieldable on top of the current board". Own-deck CONTENTS
## are fair knowledge (multiset); draw order is never consulted. Every run
## is RNG-fenced, so per-seed sim determinism holds.

const Real := preload("res://tests/fixtures/real_cards.gd")

const VANILLA_5K := "EBP01-053"
const VANILLA_5K_B := "EBP02-063"
const VANILLA_1K := "EBP01-016"


func _make_state() -> GameState:
	var gs := GameState.new()
	gs.turn_number = 5
	var p: PlayerState = gs.players[0]
	p.current_monster = Real.instance("EBP02-052")
	p.monster_zone = 8
	p.rage = 0
	p.push_zone_card(0, Real.instance(VANILLA_1K))
	var deck: Array[Dictionary] = [
		Real.instance(VANILLA_5K, 0), Real.instance(VANILLA_5K, 1),
	]
	p.main_deck = deck
	return gs


func test_instances_to_entries_counts_by_base_id() -> void:
	var entries := KaijuCounterOracle.instances_to_entries([
		Real.instance(VANILLA_5K, 0), Real.instance(VANILLA_5K, 1),
		Real.instance(VANILLA_1K), {},
	])
	# Sorted by base id, empties skipped.
	assert_array(entries).is_equal([
		{"card_number": VANILLA_1K, "quantity": 1},
		{"card_number": VANILLA_5K, "quantity": 2},
	])


func test_max_remaining_locks_board_and_fills_from_deck() -> void:
	# Locked 1000 body + two 5000s in the deck: 11000, engine-exact.
	var gs := _make_state()
	var oracle := KaijuCounterOracle.new()
	assert_int(oracle.max_remaining(gs, 0)).is_equal(11000)


func test_max_remaining_include_hand_toggle() -> void:
	var gs := _make_state()
	var hand: Array[Dictionary] = [Real.instance(VANILLA_5K_B)]
	gs.players[0].hand = hand
	var oracle := KaijuCounterOracle.new()
	assert_int(oracle.max_remaining(gs, 0, true)).is_equal(16000)
	assert_int(oracle.max_remaining(gs, 0, false)).is_equal(11000)


func test_max_remaining_deterministic_and_cached() -> void:
	var gs := _make_state()
	var first := KaijuCounterOracle.new().max_remaining(gs, 0)
	var oracle := KaijuCounterOracle.new()
	assert_int(oracle.max_remaining(gs, 0)).is_equal(first)
	# Second call on the same composition hits the cache (same value).
	assert_int(oracle.max_remaining(gs, 0)).is_equal(first)


func test_rng_fence_restores_deterministic_stream() -> void:
	# The post-call global RNG stream must depend only on the composition,
	# never on the pre-call stream — twice from different seeds, identical
	# randi() afterwards.
	var gs := _make_state()
	seed(111)
	var total_a := KaijuCounterOracle.new().max_remaining(gs, 0)
	var first := randi()
	seed(222)
	var total_b := KaijuCounterOracle.new().max_remaining(gs, 0)
	assert_int(total_b).is_equal(total_a)
	assert_int(randi()).is_equal(first)


func test_deck_ceiling_unconstrained() -> void:
	# 8 x 5000 in deck+hand, 7 fieldable zones: 35000 regardless of board.
	var p := PlayerState.new(0)
	var deck: Array[Dictionary] = []
	for i in range(6):
		deck.append(Real.instance(VANILLA_5K, i))
	p.main_deck = deck
	var hand: Array[Dictionary] = [
		Real.instance(VANILLA_5K_B, 0), Real.instance(VANILLA_5K_B, 1),
	]
	p.hand = hand
	assert_int(KaijuCounterOracle.deck_ceiling(p)).is_equal(35000)
