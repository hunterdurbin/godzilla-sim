extends GdUnitTestSuite

## ModifierBreakdown: per-source attribution for the card zoom overlay.
## Verifies that the EffectQueries breakdown ports attribute each modifier
## to the right source card, that their sums stay identical to the existing
## aggregate getters (the refactor invariant), and that the collect/normalize
## helpers used by the multiplayer client path behave.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _wire(state: GameState) -> EffectHandler:
	return States.make_session(state)["effect_handler"]


## owner -2 / src_loc "|skip|" = don't check (entries assembled outside the
## queries layer).
func _assert_entry(e: Dictionary, stat: String, amount: int, source: String, zone: int = -1, owner: int = -2, src_loc: String = "|skip|") -> void:
	assert_str(str(e.get("stat"))).is_equal(stat)
	assert_int(int(e.get("amount"))).is_equal(amount)
	assert_str(str(e.get("source"))).is_equal(source)
	assert_int(int(e.get("zone"))).is_equal(zone)
	if owner != -2:
		assert_int(int(e.get("owner", -1))).is_equal(owner)
	if src_loc != "|skip|":
		assert_str(str(e.get("src_loc", ""))).is_equal(src_loc)


func _assert_zone_cp_sums_match(handler: EffectHandler, player_id: int) -> void:
	var breakdown: Array = handler.get_zone_cp_breakdown(player_id)
	var sums: Array = handler.get_zone_cp_modifiers(player_id)
	for i in range(8):
		assert_int(ModifierBreakdown.sum(breakdown[i])) \
			.override_failure_message("zone %d: sum(breakdown) != get_zone_cp_modifiers" % i) \
			.is_equal(sums[i])


# --- Zone CP breakdown ---


func test_zone_cp_own_effect_source() -> void:
	# EBP01-017: +3000 CP while in zone 8 (index 7).
	var card := Real.instance("EBP01-017")
	var state := States.make_state({"p0": {"zone_cards": {7: card}}})
	var handler := _wire(state)

	var breakdown: Array = handler.get_zone_cp_breakdown(0)
	assert_int(breakdown[7].size()).is_equal(1)
	_assert_entry(breakdown[7][0], "cp", 3000, "EBP01-017", 7, 0, "z7")
	for i in range(7):
		assert_int(breakdown[i].size()).is_equal(0)
	_assert_zone_cp_sums_match(handler, 0)


func test_zone_cp_field_source_from_strategy() -> void:
	# EBP04-082 <Your Turn>: non-blue battle cards adjacent to own monster
	# gain +3000. Monster at zone 1 (idx 0) -> adjacent = [1].
	var strategy := Real.instance("EBP04-082")
	var buffed := Cards.battle(2, 4000, "PLAIN-1")
	var state := States.make_state({"p0": {
		"zone_cards": {1: buffed},
		"strategy_zones": [strategy],
	}})
	var handler := _wire(state)

	var breakdown: Array = handler.get_zone_cp_breakdown(0)
	assert_int(breakdown[1].size()).is_equal(1)
	_assert_entry(breakdown[1][0], "cp", 3000, "EBP04-082", 1, 0, "strategy")
	_assert_zone_cp_sums_match(handler, 0)

	# Not active on the opponent's turn — entry disappears.
	state.current_player_id = 1
	assert_int(handler.get_zone_cp_breakdown(0)[1].size()).is_equal(0)


func test_zone_cp_doubling_after_additive() -> void:
	# P1's monster EBP02-029 doubles opponent battle cards in its column from
	# the counter phase on. P1 monster at zone 3 (idx 2) -> doubles P0 zones
	# [2, 7]. P0's EBP02-068 at idx 2 is in the opponent monster's column, so
	# its own +3000 applies first and the doubling entry reflects base + 3000.
	var mkg := Real.instance("EBP02-068")
	var base_cp: int = mkg.get("counter_power", 0)
	var state := States.make_state({
		"p0": {"zone_cards": {2: mkg}},
		"p1": {"current_monster": Real.instance("EBP02-029"), "monster_zone": 3},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var handler := _wire(state)

	var breakdown: Array = handler.get_zone_cp_breakdown(0)
	assert_int(breakdown[2].size()).is_equal(2)
	_assert_entry(breakdown[2][0], "cp", 3000, "EBP02-068", 2, 0)
	_assert_entry(breakdown[2][1], "cp_double", base_cp + 3000, "EBP02-029", 2, 1)
	_assert_zone_cp_sums_match(handler, 0)
	# Doubling total = 2 * (base + mod).
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(2 * (base_cp + 3000))


func test_zone_cp_engagement_gating_drops_own_entry() -> void:
	# EBP01-014 (P1 monster, opponent's turn, Awakening4, 2+ battle cards):
	# P0's rank <=5 cards cannot engage during the counter phase, so their
	# own-CP entries are dropped. EBP02-033 (rank 5, Awakening4 +3000) fires
	# in MAIN phase but is gated out in COUNTER.
	var little := Real.instance("EBP02-033")
	var state := States.make_state({
		"p0": {"zone_cards": {0: little}, "monster_zone": 4},
		"p1": {
			"current_monster": Real.instance("EBP01-014"),
			"monster_zone": 4,
			"zone_cards": {0: Cards.battle(2, 1000, "F-1"), 1: Cards.battle(2, 1000, "F-2")},
		},
	})
	var handler := _wire(state)

	assert_int(handler.get_zone_cp_breakdown(0)[0].size()).is_equal(1)
	_assert_entry(handler.get_zone_cp_breakdown(0)[0][0], "cp", 3000, "EBP02-033", 0)

	state.current_phase = CardEnums.GamePhase.COUNTER
	assert_int(handler.get_zone_cp_breakdown(0)[0].size()).is_equal(0)
	_assert_zone_cp_sums_match(handler, 0)


# --- Threat breakdown ---


func test_threat_breakdown_monster_source() -> void:
	# EBP02-002: +5000 threat while a strategy card is in play.
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("EBP02-002"),
		"strategy_zones": [Cards.strategy()],
	}})
	var handler := _wire(state)

	var entries: Array = handler.get_threat_level_breakdown(0)
	assert_int(entries.size()).is_equal(1)
	_assert_entry(entries[0], "threat", 5000, "EBP02-002", -1, 0)
	assert_int(ModifierBreakdown.sum(entries)).is_equal(handler.get_threat_level_modifier(0))

	state.players[0].strategy_zones[0] = {}
	assert_int(handler.get_threat_level_breakdown(0).size()).is_equal(0)


# --- Play rank breakdown ---


func test_play_rank_self_source() -> void:
	# EBP02-068: rank -2 per non-rank-23 King Ghidorah card in the discard.
	var mkg := Real.instance("EBP02-068")
	var state := States.make_state({"p0": {"hand": [mkg]}})
	state.players[0].discard_pile.append(
		Cards.battle(3, 1000, "KG-1", [CardEnums.CardTrait.KING_GHIDORAH]))
	state.players[0].discard_pile.append(
		Cards.battle(4, 1000, "KG-2", [CardEnums.CardTrait.KING_GHIDORAH]))
	var handler := _wire(state)

	var entries: Array = handler.get_play_rank_breakdown(0, mkg)
	assert_int(entries.size()).is_equal(1)
	_assert_entry(entries[0], "play_rank", -4, "EBP02-068")
	assert_int(ModifierBreakdown.sum(entries)).is_equal(handler.get_play_rank_modifier(0, mkg))


func test_play_rank_strategy_source() -> void:
	# EBP02-039 <Your Turn>: Biollante battle cards cost -3 from hand.
	var biollante := Real.instance("EBP01-048")
	var state := States.make_state({"p0": {
		"hand": [biollante],
		"strategy_zones": [Real.instance("EBP02-039")],
	}})
	var handler := _wire(state)

	var entries: Array = handler.get_play_rank_breakdown(0, biollante)
	assert_int(entries.size()).is_equal(1)
	_assert_entry(entries[0], "play_rank", -3, "EBP02-039")
	assert_int(ModifierBreakdown.sum(entries)).is_equal(handler.get_play_rank_modifier(0, biollante))


func test_play_rank_stacking_self_skip() -> void:
	# EBP03-051 stacks on a Little Godzilla zone card: the -2 is zone-specific
	# (get_zone_play_rank_breakdown), never a global self entry.
	var junior := Real.instance("EBP03-051")
	var state := States.make_state({"p0": {
		"hand": [junior],
		"zone_cards": {3: Real.instance("EBP02-033")},
	}})
	var handler := _wire(state)

	assert_int(handler.get_play_rank_breakdown(0, junior).size()).is_equal(0)
	assert_int(handler.get_play_rank_modifier(0, junior)).is_equal(0)

	var zone_entries: Array = handler.get_zone_play_rank_breakdown(0, junior)
	assert_int(zone_entries.size()).is_equal(1)
	_assert_entry(zone_entries[0], "zone_play_rank", -2, "EBP03-051", 3)


# --- Strategy hand rank breakdown ---


func test_strategy_hand_rank_source_and_filter() -> void:
	# EBP04-028 (P1 monster) <Opponent's Turn>: strategies in the opponent's
	# hand gain +3 rank. TRIGGER_FILTERS gate by turn and hand owner.
	var held := Cards.strategy(4, "HELD-1")
	var state := States.make_state({
		"p0": {"hand": [held]},
		"p1": {"current_monster": Real.instance("EBP04-028")},
	})
	var handler := _wire(state)

	var entries: Array = handler.get_strategy_hand_rank_breakdown(0, held)
	assert_int(entries.size()).is_equal(1)
	_assert_entry(entries[0], "play_rank", 3, "EBP04-028", -1, 1, "monster")
	assert_int(ModifierBreakdown.sum(entries)) \
		.is_equal(handler.get_strategy_hand_rank_modifier(0, held))

	# On P1's own turn the own_turn=false filter drops the source.
	state.current_player_id = 1
	assert_int(handler.get_strategy_hand_rank_breakdown(0, held).size()).is_equal(0)


func test_strategy_hand_rank_one_entry_per_copy() -> void:
	# EBP04-068 (Kaizer Ghidorah) <Your Turn>: strategies in hand get -1 per
	# distinct battle color in the discard, PER COPY in play. Three copies
	# must each produce their own entry with their own board location — the
	# UI shows every instance as a separate source.
	var held := Cards.strategy(6, "HELD-1")
	var state := States.make_state({"p0": {
		"hand": [held],
		"zone_cards": {
			1: Real.instance("EBP04-068", 0),
			3: Real.instance("EBP04-068", 1),
			5: Real.instance("EBP04-068", 2),
		},
	}})
	state.players[0].discard_pile.append(Cards.battle(2, 1000, "D-RED"))
	var green := Cards.battle(2, 1000, "D-GRN")
	green["colors"] = [CardEnums.CardColor.GREEN]
	state.players[0].discard_pile.append(green)
	var handler := _wire(state)

	var entries: Array = handler.get_strategy_hand_rank_breakdown(0, held)
	assert_int(entries.size()).is_equal(3)
	_assert_entry(entries[0], "play_rank", -2, "EBP04-068", -1, 0, "z1")
	_assert_entry(entries[1], "play_rank", -2, "EBP04-068", -1, 0, "z3")
	_assert_entry(entries[2], "play_rank", -2, "EBP04-068", -1, 0, "z5")
	assert_int(ModifierBreakdown.sum(entries)).is_equal(-6)
	assert_int(handler.get_strategy_hand_rank_modifier(0, held)).is_equal(-6)


# --- Field rank breakdown ---


func test_field_rank_opponent_monster_source_with_clamp() -> void:
	# EBP03-025 (P1 monster) <Your Turn>: opponent battle cards get rank -1.
	# Rank-1 cards clamp at effective rank 1 (delta 0 -> no entry).
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {0: Cards.battle(3, 1000, "R3"), 4: Cards.battle(1, 1000, "R1")}},
		"p1": {"current_monster": Real.instance("EBP03-025")},
	})
	var handler := _wire(state)

	var breakdown: Array = handler.get_field_rank_breakdown(0)
	assert_int(breakdown[0].size()).is_equal(1)
	_assert_entry(breakdown[0][0], "field_rank", -1, "EBP03-025", 0, 1)
	assert_int(breakdown[4].size()).is_equal(0)
	var sums: Array = handler.get_zone_rank_modifiers(0)
	for i in range(8):
		assert_int(ModifierBreakdown.sum(breakdown[i])).is_equal(sums[i])


# --- Hand-time counter power preview (HAND_CP_PREVIEW opt-in) ---


func test_hand_cp_preview_rage_scaling() -> void:
	# EBP01-075: +3000 CP per own rage — placement-independent, tagged.
	var kotm := Real.instance("EBP01-075")
	var state := States.make_state({"p0": {"hand": [kotm], "rage": 2}})
	var handler := _wire(state)

	assert_int(handler.get_hand_cp_preview(0, kotm)).is_equal(6000)

	state.players[0].rage = 0
	assert_int(handler.get_hand_cp_preview(0, kotm)).is_equal(0)


func test_hand_cp_preview_awakening() -> void:
	# EBP01-046: +3000 at Awakening6 — knowable from hand via monster_zone.
	var card := Real.instance("EBP01-046")
	var state := States.make_state({"p0": {"hand": [card], "monster_zone": 6}})
	var handler := _wire(state)

	assert_int(handler.get_hand_cp_preview(0, card)).is_equal(3000)

	state.players[0].monster_zone = 5
	assert_int(handler.get_hand_cp_preview(0, card)).is_equal(0)


func test_hand_cp_preview_excludes_untagged_and_non_battle() -> void:
	# EBP01-017's CP mod is zone-dependent (zone 8) — not tagged, so no
	# preview even though the effect would return 0 from hand anyway.
	var zone_card := Real.instance("EBP01-017")
	# Strategy cards never get a CP preview.
	var strategy := Real.instance("EBP02-039")
	var state := States.make_state({"p0": {"hand": [zone_card, strategy], "rage": 3}})
	var handler := _wire(state)

	assert_int(handler.get_hand_cp_preview(0, zone_card)).is_equal(0)
	assert_int(handler.get_hand_cp_preview(0, strategy)).is_equal(0)


func test_hand_entries_include_cp_preview() -> void:
	var kotm := Real.instance("EBP01-075")
	var state := States.make_state({"p0": {"hand": [kotm], "rage": 2}})
	var handler := _wire(state)

	var entries: Array = ModifierBreakdown.hand_entries(handler, 0, kotm)
	var cp_entries: Array = entries.filter(func(e: Dictionary) -> bool: return e.get("stat") == "cp")
	assert_int(cp_entries.size()).is_equal(1)
	_assert_entry(cp_entries[0], "cp", 6000, "EBP01-075", -1, 0)


# --- Variable printed bases ("counter power / threat level X") ---


func _colored_battle(color: int, id: String, rank: int = 2, cp: int = 2000) -> Dictionary:
	var card := Cards.battle(rank, cp, id)
	card["colors"] = [color]
	return card


func test_zone_cp_variable_base_entry() -> void:
	# EBP04-047: counter power X = 3000 x distinct colors among OTHER battle
	# cards — a variable BASE (cp_var_base), not a "cp" modifier.
	var card := Real.instance("EBP04-047")
	var state := States.make_state({"p0": {"zone_cards": {
		2: card,
		1: _colored_battle(CardEnums.CardColor.RED, "C-R"),
		3: _colored_battle(CardEnums.CardColor.GREEN, "C-G"),
		4: _colored_battle(CardEnums.CardColor.WHITE, "C-W"),
	}}})
	var handler := _wire(state)

	var breakdown: Array = handler.get_zone_cp_breakdown(0)
	assert_int(breakdown[2].size()).is_equal(1)
	_assert_entry(breakdown[2][0], "cp_var_base", 9000, "EBP04-047", 2, 0, "z2")
	_assert_zone_cp_sums_match(handler, 0)
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(9000)
	assert_int(ModifierBreakdown.variable_zone_bases(breakdown)[2]).is_equal(9000)
	assert_int(ModifierBreakdown.variable_zone_bases(breakdown)[1]).is_equal(-1)


func test_zone_cp_variable_base_zero_still_reported() -> void:
	# Alone on the board X = 0 — the entry must survive (X = 0 is a real
	# value the UI shows, not "no modifier").
	var card := Real.instance("EBP04-047")
	var state := States.make_state({"p0": {"zone_cards": {2: card}}})
	var handler := _wire(state)

	var breakdown: Array = handler.get_zone_cp_breakdown(0)
	assert_int(breakdown[2].size()).is_equal(1)
	_assert_entry(breakdown[2][0], "cp_var_base", 0, "EBP04-047", 2, 0, "z2")
	assert_int(handler.get_effective_zone_cp(0, 2)).is_equal(0)
	assert_int(ModifierBreakdown.variable_zone_bases(breakdown)[2]).is_equal(0)


func test_variable_base_survives_engagement_gating_and_is_restricted() -> void:
	# EBP01-014 (P1 monster) restricts rank <=5 from engaging in the counter
	# phase. The cp_var_base entry is a printed base, so it stays in the
	# breakdown — the exclusion happens via get_engagement_restricted_cp,
	# which must subtract the resolved X alongside printed bases. Net CP: 0.
	var card := Real.instance("EBP04-047")
	var state := States.make_state({
		"p0": {"zone_cards": {
			2: card,
			1: _colored_battle(CardEnums.CardColor.RED, "C-R"),
			3: _colored_battle(CardEnums.CardColor.GREEN, "C-G"),
			4: _colored_battle(CardEnums.CardColor.WHITE, "C-W"),
		}},
		"p1": {
			"current_monster": Real.instance("EBP01-014"),
			"monster_zone": 4,
			"zone_cards": {0: Cards.battle(2, 1000, "F-1"), 1: Cards.battle(2, 1000, "F-2")},
		},
	})
	state.current_phase = CardEnums.GamePhase.COUNTER
	var handler := _wire(state)

	var breakdown: Array = handler.get_zone_cp_breakdown(0)
	assert_int(breakdown[2].size()).is_equal(1)
	_assert_entry(breakdown[2][0], "cp_var_base", 9000, "EBP04-047", 2, 0, "z2")
	# Restricted subtraction: 3 x 2000 printed + 9000 resolved X.
	assert_int(handler.get_engagement_restricted_cp(0)).is_equal(15000)
	# Counter math (base total + modifiers - restricted) nets to zero.
	var net: int = state.players[0].get_total_counter_power() \
		+ handler.get_counter_power_modifier(0) - handler.get_engagement_restricted_cp(0)
	assert_int(net).is_equal(0)


func test_threat_variable_base_entry() -> void:
	# EBP04-031: threat level X = 3000 x distinct colors among own battle
	# cards — a variable BASE (threat_var_base), not a "threat" modifier.
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("EBP04-031"),
		"zone_cards": {
			0: _colored_battle(CardEnums.CardColor.RED, "C-R"),
			1: _colored_battle(CardEnums.CardColor.BLUE, "C-B"),
		},
	}})
	var handler := _wire(state)

	var entries: Array = handler.get_threat_level_breakdown(0)
	assert_int(entries.size()).is_equal(1)
	_assert_entry(entries[0], "threat_var_base", 6000, "EBP04-031", -1, 0, "monster")
	assert_int(handler.get_threat_level_modifier(0)).is_equal(6000)
	assert_int(handler.get_effective_threat_level(0)) \
		.is_equal(state.players[0].get_threat_level() + 6000)
	assert_int(ModifierBreakdown.variable_base(entries, "threat_var_base")).is_equal(6000)

	# No battle cards -> X = 0, entry stays.
	state.players[0].clear_zone(0)
	state.players[0].clear_zone(1)
	var zeroed: Array = handler.get_threat_level_breakdown(0)
	assert_int(zeroed.size()).is_equal(1)
	_assert_entry(zeroed[0], "threat_var_base", 0, "EBP04-031", -1, 0, "monster")


func test_hand_entries_include_variable_base_preview() -> void:
	# EBP03-067 in hand: X counts every zone (no self-zone to exclude yet).
	var card := Real.instance("EBP03-067")
	var state := States.make_state({"p0": {
		"hand": [card],
		"zone_cards": {
			0: _colored_battle(CardEnums.CardColor.RED, "C-R"),
			1: _colored_battle(CardEnums.CardColor.GREEN, "C-G"),
		},
	}})
	var handler := _wire(state)

	assert_int(handler.get_hand_variable_base_cp(0, card)).is_equal(6000)
	var entries: Array = ModifierBreakdown.hand_entries(handler, 0, card)
	var vb: Array = entries.filter(func(e: Dictionary) -> bool: return e.get("stat") == "cp_var_base")
	assert_int(vb.size()).is_equal(1)
	_assert_entry(vb[0], "cp_var_base", 6000, "EBP03-067", -1, 0)


# --- build_all / collect / normalize (multiplayer packing helpers) ---


func test_build_all_shape_and_hand_privacy() -> void:
	var held := Cards.strategy(4, "HELD-1")
	var state := States.make_state({
		"p0": {"hand": [held], "zone_cards": {7: Real.instance("EBP01-017")}},
		"p1": {"hand": [Cards.strategy(2, "OPP-1")]},
	})
	var handler := _wire(state)

	var packed: Dictionary = ModifierBreakdown.build_all(handler, state, 0)
	assert_int((packed["zone_cp"] as Array).size()).is_equal(2)
	assert_int((packed["zone_cp"][0] as Array).size()).is_equal(8)
	_assert_entry(packed["zone_cp"][0][7][0], "cp", 3000, "EBP01-017", 7)
	# Viewer 0 gets hand entries; the opponent's hand stays empty.
	assert_int((packed["hand"][0] as Array).size()).is_equal(1)
	assert_int((packed["hand"][1] as Array).size()).is_equal(0)


func test_collect_selects_by_location() -> void:
	var zone_entry := {"stat": "cp", "amount": 3000, "source": "A", "source_name": "A", "zone": 2}
	var threat_entry := {"stat": "threat", "amount": 5000, "source": "M", "source_name": "M", "zone": -1}
	var hand_entry := {"stat": "play_rank", "amount": -2, "source": "S", "source_name": "S", "zone": -1}
	var packed := {
		"zone_cp": [[[], [], [zone_entry], [], [], [], [], []], [[], [], [], [], [], [], [], []]],
		"field_rank": [[[], [], [], [], [], [], [], []], [[], [], [], [], [], [], [], []]],
		"threat": [[threat_entry], []],
		"monster_cp": [[], []],
		"strategy_cp": [[[]], [[]]],
		"hand": [[[hand_entry]], []],
	}

	var zone_hits := ModifierBreakdown.collect(packed, 0, "zone", 2)
	assert_int(zone_hits.size()).is_equal(1)
	assert_str(str(zone_hits[0]["source"])).is_equal("A")

	var monster_hits := ModifierBreakdown.collect(packed, 0, "monster", -1)
	assert_int(monster_hits.size()).is_equal(1)
	assert_str(str(monster_hits[0]["source"])).is_equal("M")

	var hand_hits := ModifierBreakdown.collect(packed, 0, "hand", 0)
	assert_int(hand_hits.size()).is_equal(1)
	assert_str(str(hand_hits[0]["source"])).is_equal("S")

	# Out-of-range / missing selections come back empty, never crash.
	assert_int(ModifierBreakdown.collect(packed, 1, "hand", 0).size()).is_equal(0)
	assert_int(ModifierBreakdown.collect(packed, 0, "zone", 9).size()).is_equal(0)
	assert_int(ModifierBreakdown.collect({}, 0, "zone", 0).size()).is_equal(0)


func test_normalize_casts_float_amounts() -> void:
	# JSON-coerced floats (client armor) must come back as ints.
	var packed := {
		"threat": [[{"stat": "threat", "amount": 5000.0, "source": "M", "source_name": "M", "zone": -1.0, "owner": 1.0}], []],
	}
	var normalized := ModifierBreakdown.normalize(packed)
	var e: Dictionary = normalized["threat"][0][0]
	assert_bool(e["amount"] is int).is_true()
	assert_int(e["amount"]).is_equal(5000)
	assert_bool(e["zone"] is int).is_true()
	assert_int(e["zone"]).is_equal(-1)
	assert_bool(e["owner"] is int).is_true()
	assert_int(e["owner"]).is_equal(1)
