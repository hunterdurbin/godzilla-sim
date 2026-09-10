extends GdUnitTestSuite

## BoardEditor: free-form debug mutation engine behind the F4 board editor.
## Covers instance minting, container ops (zones / strategy / monster / hand /
## deck / discard), PlayerState signal emission, effect registration, and the
## GameSerializer snapshot round-trip for editor-minted cards.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _make(opts: Dictionary = {}) -> Dictionary:
	var state := States.make_state(opts)
	var tm := States.make_turn_manager(state, ScriptedPlayerInput.new())
	return {"state": state, "tm": tm, "ed": BoardEditor.new(tm)}


func _count_signal(sig: Signal, bucket: Array) -> void:
	sig.connect(func() -> void: bucket.append(1))


func _no_deck_names() -> Array[String]:
	var names: Array[String] = ["", ""]
	return names


## Guarded index helpers: return sentinel strings instead of hard-erroring on
## short arrays, so missing behavior fails the assertion rather than aborting
## the whole gdUnit run.
func _id_at(arr: Array, i: int) -> String:
	if i < 0 or i >= arr.size():
		return "<missing>"
	return str(arr[i].get("id", ""))


func _base_at(arr: Array, i: int) -> String:
	if i < 0 or i >= arr.size():
		return "<missing>"
	return CardUtils.base_id(arr[i])


# --- Minting ---

func test_mint_card_stamps_unique_instance_ids() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var a: Dictionary = ed.mint_card("EBP01-001")
	var b: Dictionary = ed.mint_card("EBP01-001")
	assert_str(a.get("id", "")).is_not_equal(b.get("id", ""))
	assert_str(CardUtils.base_id(a)).is_equal("EBP01-001")
	assert_str(CardUtils.base_id(b)).is_equal("EBP01-001")


func test_mint_card_survives_serializer_id_round_trip() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var card: Dictionary = ed.mint_card("EBP01-001")
	var restored: Dictionary = GameSerializer.id_to_card(card.get("id", ""))
	assert_str(CardUtils.base_id(restored)).is_equal("EBP01-001")
	assert_str(restored.get("name", "")).is_equal(CardData.get_card_by_id("EBP01-001").get("name", ""))


func test_mint_card_deep_copies_template() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var card: Dictionary = ed.mint_card("EBP01-001")
	assert_bool(card.has("traits")).is_true()
	card.get("traits", []).append(CardEnums.CardTrait.TOKEN)
	assert_bool(CardEnums.CardTrait.TOKEN in CardData.get_card_by_id("EBP01-001").get("traits", [])).is_false()


# --- Zones ---

func test_add_to_zone_top_and_bottom_ordering() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_zone(0, 3, Cards.battle(1, 5000, "FIRST"), true)
	ed.add_to_zone(0, 3, Cards.battle(1, 5000, "ON-TOP"), true)
	ed.add_to_zone(0, 3, Cards.battle(1, 5000, "UNDER"), false)
	var stack: Array = state.players[0].zones[3]
	assert_str(_id_at(stack, 0)).is_equal("ON-TOP")
	assert_str(_id_at(stack, 1)).is_equal("FIRST")
	assert_str(_id_at(stack, 2)).is_equal("UNDER")


func test_add_to_zone_emits_zones_changed() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var hits: Array = []
	_count_signal(state.players[1].zones_changed, hits)
	ed.add_to_zone(1, 0, Cards.battle(1, 5000, "A"), true)
	assert_int(hits.size()).is_equal(1)


func test_add_to_zone_registers_card_effect() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var tm: TurnManager = ctx["tm"]
	var base_id: String = Real.ids_with_effects()[0]
	var card: Dictionary = ed.mint_card(base_id)
	ed.add_to_zone(0, 0, card, true)
	var script_path: String = card.get("effect_script", "")
	assert_bool(tm.effect_handler.registry._effect_cache.has(script_path)).is_true()


func test_remove_from_zone_pops_at_index() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_zone(0, 2, Cards.battle(1, 5000, "BOTTOM"), false)
	ed.add_to_zone(0, 2, Cards.battle(1, 5000, "MID"), false)
	ed.add_to_zone(0, 2, Cards.battle(1, 5000, "LAST"), false)
	var hits: Array = []
	_count_signal(state.players[0].zones_changed, hits)
	var removed: Dictionary = ed.remove_from_zone(0, 2, 1)
	assert_str(removed.get("id", "")).is_equal("MID")
	assert_int(state.players[0].zones[2].size()).is_equal(2)
	assert_int(hits.size()).is_equal(1)


func test_remove_from_zone_invalid_index_returns_empty() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_zone(0, 2, Cards.battle(1, 5000, "KEEP"), true)
	assert_bool(ed.remove_from_zone(0, 2, 5).is_empty()).is_true()
	assert_int(state.players[0].zones[2].size()).is_equal(1)


func test_move_zone_card_reorders_within_stack() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_zone(0, 1, Cards.battle(1, 5000, "A"), false)
	ed.add_to_zone(0, 1, Cards.battle(1, 5000, "B"), false)
	ed.add_to_zone(0, 1, Cards.battle(1, 5000, "C"), false)
	ed.move_zone_card(0, 1, 2, 0)
	var stack: Array = state.players[0].zones[1]
	assert_str(_id_at(stack, 0)).is_equal("C")
	assert_str(_id_at(stack, 1)).is_equal("A")
	assert_str(_id_at(stack, 2)).is_equal("B")


func test_move_zone_stack_on_top_of_destination() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_zone(0, 0, Cards.battle(1, 5000, "SRC"), true)
	ed.add_to_zone(0, 4, Cards.battle(1, 5000, "DST"), true)
	ed.move_zone_stack(0, 0, 4, true)
	assert_int(state.players[0].zones[0].size()).is_equal(0)
	var stack: Array = state.players[0].zones[4]
	assert_str(_id_at(stack, 0)).is_equal("SRC")
	assert_str(_id_at(stack, 1)).is_equal("DST")


func test_move_zone_stack_under_destination() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_zone(0, 0, Cards.battle(1, 5000, "SRC"), true)
	ed.add_to_zone(0, 4, Cards.battle(1, 5000, "DST"), true)
	ed.move_zone_stack(0, 0, 4, false)
	var stack: Array = state.players[0].zones[4]
	assert_str(_id_at(stack, 0)).is_equal("DST")
	assert_str(_id_at(stack, 1)).is_equal("SRC")


# --- Strategy zones ---

func test_set_strategy_stamps_turn_and_registers() -> void:
	var ctx := _make({"turn_number": 5})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var hits: Array = []
	_count_signal(state.players[0].strategy_zones_changed, hits)
	var evicted: Array = ed.set_strategy(0, 1, Cards.strategy(1, "STRAT-A"))
	assert_int(evicted.size()).is_equal(0)
	assert_str(state.players[0].strategy_zones[1].get("id", "")).is_equal("STRAT-A")
	assert_int(state.players[0].strategy_zone_turn_placed[1]).is_equal(5)
	assert_int(hits.size()).is_equal(1)


func test_set_strategy_evicts_old_card_and_under_stack() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.set_strategy(0, 0, Cards.strategy(1, "OLD"))
	ed.add_under_strategy(0, 0, Cards.battle(1, 5000, "UNDER"), true)
	var evicted: Array = ed.set_strategy(0, 0, Cards.strategy(1, "NEW"))
	assert_int(evicted.size()).is_equal(2)
	assert_str(_id_at(evicted, 0)).is_equal("OLD")
	assert_str(_id_at(evicted, 1)).is_equal("UNDER")
	assert_str(state.players[0].strategy_zones[0].get("id", "")).is_equal("NEW")
	assert_int(state.players[0].strategy_zone_stacks[0].size()).is_equal(0)


func test_strategy_ops_reject_out_of_range_slot() -> void:
	# PlayerBoard renders 3 strategy slots but the engine has only 2 zones —
	# a Strategy3 click reaches the editor with slot index 2 and must no-op.
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	assert_array(ed.set_strategy(0, 2, Cards.strategy(1, "S3"))).is_empty()
	ed.add_under_strategy(0, 2, Cards.battle(1, 5000, "U3"), true)
	assert_bool(ed.remove_under_strategy(0, 2, 0).is_empty()).is_true()
	assert_array(ed.clear_strategy(0, 2)).is_empty()
	assert_int(state.players[0].strategy_zones.size()).is_equal(2)
	assert_int(state.players[0].strategy_zone_stacks.size()).is_equal(2)


func test_clear_strategy_returns_card_and_stack() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.set_strategy(0, 0, Cards.strategy(1, "S"))
	ed.add_under_strategy(0, 0, Cards.battle(1, 5000, "U"), true)
	var cleared: Array = ed.clear_strategy(0, 0)
	assert_int(cleared.size()).is_equal(2)
	assert_bool(state.players[0].strategy_zones[0].is_empty()).is_true()
	assert_int(state.players[0].strategy_zone_stacks[0].size()).is_equal(0)


func test_under_strategy_ordering_and_removal() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.set_strategy(0, 0, Cards.strategy(1, "S"))
	ed.add_under_strategy(0, 0, Cards.battle(1, 5000, "FIRST"), true)
	ed.add_under_strategy(0, 0, Cards.battle(1, 5000, "TOP"), true)
	ed.add_under_strategy(0, 0, Cards.battle(1, 5000, "BOTTOM"), false)
	var stack: Array = state.players[0].strategy_zone_stacks[0]
	assert_str(_id_at(stack, 0)).is_equal("TOP")
	assert_str(_id_at(stack, 2)).is_equal("BOTTOM")
	var removed: Dictionary = ed.remove_under_strategy(0, 0, 0)
	assert_str(removed.get("id", "")).is_equal("TOP")
	assert_int(stack.size()).is_equal(2)


# --- Monster ---

func test_set_current_monster_old_to_stack_top() -> void:
	var ctx := _make({"p0": {"current_monster": Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "OLD")}})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var hits: Array = []
	_count_signal(state.players[0].monster_changed, hits)
	var displaced: Dictionary = ed.set_current_monster(0, Cards.monster(2, 8000, [CardEnums.CardTrait.GODZILLA], "NEW"), "stack_top")
	assert_str(state.players[0].current_monster.get("id", "")).is_equal("NEW")
	assert_str(_id_at(state.players[0].monster_stack, 0)).is_equal("OLD")
	assert_str(displaced.get("id", "")).is_equal("OLD")
	assert_int(hits.size()).is_equal(1)


func test_set_current_monster_old_to_discard() -> void:
	var ctx := _make({"p0": {"current_monster": Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "OLD")}})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.set_current_monster(0, Cards.monster(2, 8000, [CardEnums.CardTrait.GODZILLA], "NEW"), "discard")
	assert_int(state.players[0].monster_stack.size()).is_equal(0)
	assert_str(_id_at(state.players[0].discard_pile, 0)).is_equal("OLD")


func test_set_current_monster_empty_removes_monster() -> void:
	var ctx := _make({"p0": {"current_monster": Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "OLD")}})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var displaced: Dictionary = ed.set_current_monster(0, {}, "remove")
	assert_bool(state.players[0].current_monster.is_empty()).is_true()
	assert_str(displaced.get("id", "")).is_equal("OLD")


func test_stack_under_monster_index_semantics() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.stack_under_monster(0, Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "BOTTOM"), -1)
	ed.stack_under_monster(0, Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "BELOW-TOP"), 0)
	ed.stack_under_monster(0, Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "LAST"), -1)
	var stack: Array = state.players[0].monster_stack
	assert_str(_id_at(stack, 0)).is_equal("BELOW-TOP")
	assert_str(_id_at(stack, 1)).is_equal("BOTTOM")
	assert_str(_id_at(stack, 2)).is_equal("LAST")


func test_remove_from_monster_stack() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.stack_under_monster(0, Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "A"), -1)
	ed.stack_under_monster(0, Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "B"), -1)
	var removed: Dictionary = ed.remove_from_monster_stack(0, 0)
	assert_str(removed.get("id", "")).is_equal("A")
	assert_int(state.players[0].monster_stack.size()).is_equal(1)


func test_promote_from_stack_swaps_with_current() -> void:
	var ctx := _make({"p0": {"current_monster": Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "CUR")}})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.stack_under_monster(0, Cards.monster(2, 8000, [CardEnums.CardTrait.GODZILLA], "STACKED"), 0)
	ed.promote_from_stack(0, 0, "stack_top")
	assert_str(state.players[0].current_monster.get("id", "")).is_equal("STACKED")
	assert_str(_id_at(state.players[0].monster_stack, 0)).is_equal("CUR")
	assert_int(state.players[0].monster_stack.size()).is_equal(1)


func test_set_monster_zone_clamps_to_1_8() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var hits: Array = []
	_count_signal(state.players[0].monster_changed, hits)
	await ed.set_monster_zone(0, 12)
	assert_int(state.players[0].monster_zone).is_equal(8)
	await ed.set_monster_zone(0, -3)
	assert_int(state.players[0].monster_zone).is_equal(1)
	assert_int(hits.size()).is_equal(2)


func test_set_monster_zone_crushes_destination_stack_via_engine() -> void:
	# Rule 11.3: battle cards sharing a zone with the arriving monster are
	# crushed — destroyed to the discard with the engine's resolution path.
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var tm: TurnManager = ctx["tm"]
	ed.add_to_zone(0, 3, Cards.battle(1, 5000, "VICTIM-TOP"), true)
	ed.add_to_zone(0, 3, Cards.battle(1, 5000, "VICTIM-UNDER"), false)
	var crushed: Array = []
	tm.events.battle_card_crushed.connect(func(pid: int, zone: int, card: Dictionary) -> void:
		crushed.append([pid, zone, card.get("id", "")]))

	await ed.set_monster_zone(0, 4)

	assert_int(state.players[0].monster_zone).is_equal(4)
	assert_int(state.players[0].zones[3].size()).is_equal(0)
	var discard_ids: Array = state.players[0].discard_pile.map(func(c: Dictionary) -> String: return str(c.get("id", "")))
	assert_array(discard_ids).contains(["VICTIM-TOP", "VICTIM-UNDER"])
	assert_int(crushed.size()).is_equal(1)
	var first_crushed: String = str(crushed[0][2]) if not crushed.is_empty() else "<missing>"
	assert_str(first_crushed).is_equal("VICTIM-TOP")
	assert_int(state.players[0].cards_destroyed_this_turn.size()).is_equal(1)


func test_set_monster_zone_leaves_opponent_under_monster_cards_alone() -> void:
	# Crush fires only for the MOVING monster's destination. A battle card
	# deliberately stacked in the opponent's monster zone must survive the
	# opponent's crush half of the engine rule action.
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var p2_zone_idx: int = state.players[1].monster_zone - 1
	ed.add_to_zone(1, p2_zone_idx, Cards.battle(1, 5000, "P2-UNDER-MON"), true)

	await ed.set_monster_zone(0, 4)

	assert_int(state.players[0].monster_zone).is_equal(4)
	assert_str(_id_at(state.players[1].zones[p2_zone_idx], 0)).is_equal("P2-UNDER-MON")
	assert_int(state.players[1].discard_pile.size()).is_equal(0)


func test_set_monster_zone_monster_stack_travels_and_zone_cards_stay() -> void:
	# Cards "under the monster" live in monster_stack, which moves with the
	# monster implicitly. Residual cards in the monster's old ZONE array
	# (e.g. destroy-replacement survivors) stay behind, engine-style, and
	# are not crushed by the departure; the destination stack is.
	var ctx := _make({"p0": {"monster_zone": 2}})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.stack_under_monster(0, Cards.battle(1, 5000, "IN-STACK"), 0)
	ed.add_to_zone(0, 1, Cards.battle(1, 5000, "LEFT-BEHIND"), true)
	ed.add_to_zone(0, 4, Cards.battle(1, 5000, "VICTIM"), true)

	await ed.set_monster_zone(0, 5)

	assert_int(state.players[0].monster_zone).is_equal(5)
	assert_str(_id_at(state.players[0].monster_stack, 0)).is_equal("IN-STACK")
	assert_str(_id_at(state.players[0].zones[1], 0)).is_equal("LEFT-BEHIND")
	assert_int(state.players[0].zones[4].size()).is_equal(0)
	assert_str(_id_at(state.players[0].discard_pile, 0)).is_equal("VICTIM")


# --- Hand / deck / discard ---

func test_hand_add_and_remove() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var hits: Array = []
	_count_signal(state.players[0].hand_changed, hits)
	ed.add_to_hand(0, Cards.battle(1, 5000, "A"))
	ed.add_to_hand(0, Cards.battle(1, 5000, "B"))
	var removed: Dictionary = ed.remove_from_hand(0, 0)
	assert_str(removed.get("id", "")).is_equal("A")
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_int(hits.size()).is_equal(3)


func test_deck_add_index_semantics() -> void:
	var ctx := _make({"p0": {"main_deck": [Cards.battle(1, 5000, "EXISTING")]}})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_deck(0, Cards.battle(1, 5000, "TOP"), 0)
	ed.add_to_deck(0, Cards.battle(1, 5000, "BOTTOM"), -1)
	var deck: Array = state.players[0].main_deck
	assert_str(_id_at(deck, 0)).is_equal("TOP")
	assert_str(_id_at(deck, 1)).is_equal("EXISTING")
	assert_str(_id_at(deck, 2)).is_equal("BOTTOM")


func test_reorder_deck_applies_permutation() -> void:
	var ctx := _make({"p0": {"main_deck": [
		Cards.battle(1, 5000, "A"), Cards.battle(1, 5000, "B"), Cards.battle(1, 5000, "C"),
	]}})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var deck: Array = state.players[0].main_deck
	var hits: Array = []
	_count_signal(state.players[0].deck_changed, hits)
	var ok: bool = ed.reorder_deck(0, [deck[2], deck[0], deck[1]])
	assert_bool(ok).is_true()
	assert_str(_id_at(state.players[0].main_deck, 0)).is_equal("C")
	assert_int(hits.size()).is_equal(1)


func test_reorder_deck_rejects_non_permutation() -> void:
	var ctx := _make({"p0": {"main_deck": [Cards.battle(1, 5000, "A"), Cards.battle(1, 5000, "B")]}})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var ok: bool = ed.reorder_deck(0, [state.players[0].main_deck[0]])
	assert_bool(ok).is_false()
	assert_int(state.players[0].main_deck.size()).is_equal(2)


func test_discard_add_and_remove() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var hits: Array = []
	_count_signal(state.players[0].discard_changed, hits)
	ed.add_to_discard(0, Cards.battle(1, 5000, "A"))
	var removed: Dictionary = ed.remove_from_discard(0, 0)
	assert_str(removed.get("id", "")).is_equal("A")
	assert_int(state.players[0].discard_pile.size()).is_equal(0)
	assert_int(hits.size()).is_equal(2)


func test_monster_deck_add_and_remove() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var hits: Array = []
	_count_signal(state.players[0].monster_changed, hits)
	ed.add_to_monster_deck(0, Cards.monster(2, 8000, [CardEnums.CardTrait.GODZILLA], "MD-A"))
	ed.add_to_monster_deck(0, Cards.monster(3, 10000, [CardEnums.CardTrait.GODZILLA], "MD-B"))
	var removed: Dictionary = ed.remove_from_monster_deck(0, 0)
	assert_str(removed.get("id", "")).is_equal("MD-A")
	assert_str(_id_at(state.players[0].monster_deck, 0)).is_equal("MD-B")
	assert_int(hits.size()).is_equal(3)


func test_move_card_monster_deck_container() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_monster_deck(0, Cards.monster(2, 8000, [CardEnums.CardTrait.GODZILLA], "MD"))
	ed.move_card({"pid": 0, "container": "monster_deck", "index": 0},
		{"pid": 0, "container": "discard"})
	assert_int(state.players[0].monster_deck.size()).is_equal(0)
	assert_str(_id_at(state.players[0].discard_pile, 0)).is_equal("MD")


# --- Rage / flags ---

func test_set_rage_clamps_and_emits_value() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var seen: Array = []
	state.players[0].rage_changed.connect(func(v: int) -> void: seen.append(v))
	ed.set_rage(0, 4)
	ed.adjust_rage(0, -10)
	assert_int(state.players[0].rage).is_equal(0)
	assert_array(seen).contains_exactly([4, 0])


func test_set_turn_flags() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.set_turn_flag(0, "has_invaded_this_turn", true)
	ed.set_turn_flag(0, "has_played_monster_this_turn", true)
	assert_bool(state.players[0].has_invaded_this_turn).is_true()
	assert_bool(state.players[0].has_played_monster_this_turn).is_true()


# --- Cross-container mover ---

func test_move_card_zone_to_hand() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_zone(0, 5, Cards.battle(1, 5000, "MOVER"), true)
	ed.move_card({"pid": 0, "container": "zone", "zone": 5, "index": 0},
		{"pid": 1, "container": "hand"})
	assert_int(state.players[0].zones[5].size()).is_equal(0)
	assert_str(_id_at(state.players[1].hand, 0)).is_equal("MOVER")


func test_move_card_hand_to_zone_under() -> void:
	var ctx := _make({"p0": {"hand": [Cards.battle(1, 5000, "H")]}})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_zone(0, 2, Cards.battle(1, 5000, "TOP"), true)
	ed.move_card({"pid": 0, "container": "hand", "index": 0},
		{"pid": 0, "container": "zone", "zone": 2, "on_top": false})
	assert_int(state.players[0].hand.size()).is_equal(0)
	var stack: Array = state.players[0].zones[2]
	assert_str(_id_at(stack, 0)).is_equal("TOP")
	assert_str(_id_at(stack, 1)).is_equal("H")


func test_move_card_discard_to_deck_top() -> void:
	var ctx := _make()
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	ed.add_to_discard(0, Cards.battle(1, 5000, "D"))
	ed.move_card({"pid": 0, "container": "discard", "index": 0},
		{"pid": 0, "container": "deck", "index": 0})
	assert_int(state.players[0].discard_pile.size()).is_equal(0)
	assert_str(_id_at(state.players[0].main_deck, 0)).is_equal("D")


# --- Snapshot round-trip ---

func test_editor_state_survives_serializer_round_trip() -> void:
	var ctx := _make({"p0": {"current_monster": Cards.monster(1, 6000, [CardEnums.CardTrait.GODZILLA], "CUR")}})
	var ed: BoardEditor = ctx["ed"]
	var state: GameState = ctx["state"]
	var tm: TurnManager = ctx["tm"]
	var base_id: String = Real.ids_with_effects()[0]
	ed.add_to_zone(0, 3, ed.mint_card(base_id), true)
	ed.add_to_hand(1, ed.mint_card(base_id))
	ed.stack_under_monster(0, ed.mint_card("EBP01-001"), 0)
	ed.set_rage(0, 3)
	ed.set_monster_zone(0, 6)

	var data: Dictionary = GameSerializer.serialize_game_state(
		state, 0, "solo", "", _no_deck_names(), 0, tm.effect_handler)

	var tm2 := TurnManager.new()
	tm2.player_input = ScriptedPlayerInput.new()
	tm2.setup_from_save(data)
	var p0: PlayerState = tm2.game_state.players[0]
	assert_str(_base_at(p0.zones[3], 0)).is_equal(base_id)
	assert_str(_base_at(tm2.game_state.players[1].hand, 0)).is_equal(base_id)
	assert_str(_base_at(p0.monster_stack, 0)).is_equal("EBP01-001")
	assert_int(p0.rage).is_equal(3)
	assert_int(p0.monster_zone).is_equal(6)
	tm2.teardown()


# --- Snapshot patch (Turn... dialog) ---

func test_patch_snapshot_overrides_flow_fields_only() -> void:
	var data := {"current_phase": 1, "current_player_id": 0, "turn_number": 2, "mode": "solo"}
	var patched: Dictionary = BoardEditor.patch_snapshot(data,
		{"current_phase": 3, "current_player_id": 1, "turn_number": 9, "mode": "HACKED"})
	assert_int(patched.get("current_phase", -1)).is_equal(3)
	assert_int(patched.get("current_player_id", -1)).is_equal(1)
	assert_int(patched.get("turn_number", -1)).is_equal(9)
	assert_str(str(patched.get("mode", ""))).is_equal("solo")
	# Jumping phase without an explicit sub-phase restarts the phase cleanly.
	assert_int(patched.get("current_sub_phase", -1)).is_equal(0)
