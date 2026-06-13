extends GdUnitTestSuite

## Tier B cluster: cards with phase-gated (and related play-event) triggers,
## driven through the real dispatch seams (effect_handler.trigger_phase_start /
## trigger_battle_card_played / trigger_when_invading / trigger_enter →
## registry → trigger_map → TRIGGER_FILTERS → standby resolution).
## Every TRIGGER_FILTERS-gated card here is also covered by the generic
## wrong-phase / wrong-turn gating test at the bottom.
## See classification.md for cluster membership.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


## Place the real card on player 0's board per its card type (monster →
## current_monster, battle → zone opts.zone_idx, strategy → strategy zone 0)
## and return the wired session. opts: zone_idx, current_player_id, phase,
## p0 / p1 (forwarded to States.make_state).
func _setup(card_id: String, opts: Dictionary = {}) -> Dictionary:
	var card := Real.instance(card_id)
	var p0_opts: Dictionary = opts.get("p0", {})
	if int(card.get("card_type", -1)) == CardEnums.CardType.MONSTER:
		p0_opts["current_monster"] = card
	var state := States.make_state({
		"current_player_id": opts.get("current_player_id", 0),
		"p0": p0_opts,
		"p1": opts.get("p1", {}),
	})
	match int(card.get("card_type", -1)):
		CardEnums.CardType.BATTLE:
			state.players[0].push_zone_card(int(opts.get("zone_idx", 2)), card)
		CardEnums.CardType.STRATEGY:
			state.players[0].strategy_zones[0] = card
	state.current_phase = opts.get("phase", CardEnums.GamePhase.MAIN)
	var session := States.make_session(state)
	session["state"] = state
	session["card"] = card
	return session


func _hand(count: int, prefix: String = "OPP-HAND") -> Array:
	var hand: Array = []
	for i in range(count):
		hand.append(Cards.battle(2, 3000, "%s-%d" % [prefix, i]))
	return hand


## Observable state digest for "nothing happened" gating assertions.
func _snapshot(state: GameState) -> Dictionary:
	var snap := {}
	for pid in range(2):
		var player := state.players[pid]
		var zones: Array[bool] = []
		for i in range(8):
			zones.append(player.zone_has_cards(i))
		snap["p%d" % pid] = {
			"hand": player.hand.size(),
			"deck": player.main_deck.size(),
			"discard": player.discard_pile.size(),
			"rage": player.rage,
			"monster_zone": player.monster_zone,
			"zones": zones,
		}
	return snap


# --- EBP01-001: own counter start — mill 1; +1 rage if a monster was milled ---

func test_ebp01_001_counter_start_mills_and_gains_rage_on_monster_mill(top_is_monster: bool, expected_rage: int,
		test_parameters := [
			[true, 1],
			[false, 0],
		]) -> void:
	var top := Cards.monster(2, 9000, [], "TOP-MON") if top_is_monster else Cards.battle(2, 3000, "TOP-BTL")
	var s := _setup("EBP01-001", {
		"phase": CardEnums.GamePhase.COUNTER,
		"p0": {"main_deck": [top, Cards.battle(1, 2000, "DECK-1"), Cards.battle(1, 2000, "DECK-2")]},
	})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].main_deck.size()).is_equal(2)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_int(state.players[0].rage) \
		.override_failure_message("EBP01-001: rage after milling a %s card" % ("monster" if top_is_monster else "battle")) \
		.is_equal(expected_rage)


# --- EBP01-006: opponent's counter start — destroy opp rank<=5 in own column ---

func test_ebp01_006_opponent_counter_start_destroys_low_rank_same_column() -> void:
	var s := _setup("EBP01-006", {
		"current_player_id": 1,
		"phase": CardEnums.GamePhase.COUNTER,
		"p0": {"monster_zone": 3},  # anchor idx 2 → opponent column zones [2, 7]
		"p1": {"zone_cards": {2: Cards.battle(5, 5000, "OPP-R5"), 7: Cards.battle(6, 6000, "OPP-R6")}},
	})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_bool(state.players[1].zone_has_cards(2)) \
		.override_failure_message("EBP01-006: rank 5 card in column must be destroyed").is_false()
	assert_bool(state.players[1].zone_has_cards(7)) \
		.override_failure_message("EBP01-006: rank 6 card must survive the rank<=5 cap").is_true()
	assert_int(state.players[1].discard_pile.size()).is_equal(1)


# --- EBP02-036: own end start — retreat opp monster TL<=40k if adjacent ---

func test_ebp02_036_end_start_retreats_weak_monster_only_when_adjacent(zone_idx: int, opp_tl: int, expect_retreat: bool,
		test_parameters := [
			[1, 5000, true],    # zone 2 is adjacent to monster anchor zone 1
			[4, 5000, false],   # zone 5 is not adjacent
			[1, 45000, false],  # threat level above 40k
		]) -> void:
	var s := _setup("EBP02-036", {
		"zone_idx": zone_idx,
		"phase": CardEnums.GamePhase.END,
		"p1": {"monster_zone": 2, "current_monster": Cards.monster(8, opp_tl, [], "OPP-MON")},
	})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.END)

	assert_int(state.players[1].monster_zone) \
		.override_failure_message("EBP02-036: zone_idx=%d opp_tl=%d" % [zone_idx, opp_tl]) \
		.is_equal(1 if expect_retreat else 2)


# --- EBP02-073: own turn, battle card played — destroy opp rank<=6 same column ---
# (on_battle_card_played trigger, not a phase trigger — exercised through
# trigger_battle_card_played with both turn-ownership outcomes.)

func test_ebp02_073_battle_played_destroys_column_only_on_own_turn(current_pid: int, expect_destroy: bool,
		test_parameters := [
			[0, true],
			[1, false],
		]) -> void:
	var s := _setup("EBP02-073", {
		"current_player_id": current_pid,
		"p1": {"zone_cards": {2: Cards.battle(6, 5000, "OPP-R6"), 7: Cards.battle(7, 7000, "OPP-R7")}},
	})
	var state: GameState = s["state"]
	var played := Cards.battle(3, 4000, "PLAYED")
	state.players[0].push_zone_card(2, played)  # column idx 2 → opponent zones [2, 7]

	await s["effect_handler"].trigger_battle_card_played(0, played, 2)

	assert_bool(state.players[1].zone_has_cards(2)) \
		.override_failure_message("EBP02-073: current_pid=%d" % current_pid).is_equal(not expect_destroy)
	assert_bool(state.players[1].zone_has_cards(7)) \
		.override_failure_message("EBP02-073: rank 7 card must survive the rank<=6 cap").is_true()
	assert_int(state.players[1].discard_pile.size()).is_equal(1 if expect_destroy else 0)


# --- EBP03-044 / ESD02-007 / ESD02-008: own main start — evolution from deck ---
# ESD02-010 stacked via evolution also fires its own <Enter> draw (draw_count).

func test_evolution_main_start_stacks_deck_card(card_id: String, target_id: String, draw_count: int,
		test_parameters := [
			["EBP03-044", "ESD02-010", 1],  # Mothra rank<=7 ← Mothra(imago) rank 5
			["ESD02-007", "ESD02-010", 1],  # Mothra rank<=5 ← Mothra(imago) rank 5
			["ESD02-008", "ESD02-011", 0],  # Battra rank<=6 ← Battra(imago) rank 6
		]) -> void:
	var s := _setup(card_id, {
		"zone_idx": 2,
		"p0": {
			"hand": [Cards.battle(2, 3000, "HAND-0")],
			"main_deck": [Real.instance(target_id), Cards.battle(1, 2000, "DECK-1"), Cards.battle(1, 2000, "DECK-2")],
		},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.MAIN)

	var top := state.players[0].get_zone_top_card(2)
	assert_str(CardUtils.base_id(top)) \
		.override_failure_message("%s: expected %s stacked on top via evolution" % [card_id, target_id]) \
		.is_equal(target_id)
	assert_bool(top.get("played_through_evolution", false)).is_true()
	assert_int(state.players[0].get_zone_stack(2).size()).is_equal(2)
	assert_int(input.count_calls("search_cards")).is_equal(1)
	assert_int(state.players[0].hand.size()).is_equal(1 + draw_count)
	assert_int(state.players[0].main_deck.size()).is_equal(2 - draw_count)


# --- ESD02-010: <Enter> — draw 1 only if played through evolution ---

func test_esd02_010_enter_draws_only_when_evolved(evolved: bool, expected_hand: int,
		test_parameters := [
			[true, 1],
			[false, 0],
		]) -> void:
	var s := _setup("ESD02-010", {
		"zone_idx": 2,
		"p0": {"main_deck": [Cards.battle(1, 2000, "DECK-1"), Cards.battle(1, 2000, "DECK-2")]},
	})
	var state: GameState = s["state"]
	var card: Dictionary = s["card"]
	if evolved:
		card["played_through_evolution"] = true

	await s["effect_handler"].trigger_enter(0, card)

	assert_int(state.players[0].hand.size()).is_equal(expected_hand)


# --- EBP04-008: own counter start + Awakening8 — opponent discards to 3 ---

func test_ebp04_008_counter_start_awakening8_discards_opponent_to_three(monster_zone: int, expected_opp_hand: int,
		test_parameters := [
			[8, 3],
			[7, 5],  # not awakened — body condition gates
		]) -> void:
	var s := _setup("EBP04-008", {
		"phase": CardEnums.GamePhase.COUNTER,
		"p0": {"monster_zone": monster_zone},
		"p1": {"hand": _hand(5)},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[1].hand.size()) \
		.override_failure_message("EBP04-008: opponent hand with monster_zone=%d" % monster_zone) \
		.is_equal(expected_opp_hand)
	assert_int(state.players[1].discard_pile.size()).is_equal(5 - expected_opp_hand)
	assert_int(input.count_calls("choose_hand_discards")).is_equal(1 if expected_opp_hand < 5 else 0)
	if expected_opp_hand < 5:
		assert_int(input.calls[0]["player_id"]) \
			.override_failure_message("EBP04-008: the OPPONENT picks the discards").is_equal(1)


# --- EBP02-001: opponent's counter start — may discard hand strategy for +1 rage ---
# (Listed under rage_trigger in classification.md, but it is an on_phase_start
# trigger — reclassify to phase_trigger.)

func test_ebp02_001_opponent_counter_start_discards_strategy_to_gain_rage() -> void:
	var s := _setup("EBP02-001", {
		"current_player_id": 1,
		"phase": CardEnums.GamePhase.COUNTER,
		"p0": {"hand": [Cards.strategy(2, "HAND-STR"), Cards.battle(2, 3000, "HAND-BTL")]},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].trigger_phase_start(CardEnums.GamePhase.COUNTER)

	assert_int(state.players[0].rage).is_equal(1)
	assert_int(state.players[0].hand.size()).is_equal(1)
	assert_str(state.players[0].hand[0]["id"]).is_equal("HAND-BTL")
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_str(state.players[0].discard_pile[0]["id"]).is_equal("HAND-STR")
	assert_int(input.count_calls("select_hand_card")).is_equal(1)


# --- ESD01-004: <When Invading> + rage>=2 — opponent discards to 2 ---
# (when_invading trigger, not a phase trigger — reclassify.)

func test_esd01_004_when_invading_discards_opponent_to_two_if_raged(rage: int, expected_opp_hand: int,
		test_parameters := [
			[2, 2],
			[1, 5],
		]) -> void:
	var s := _setup("ESD01-004", {
		"p0": {"rage": rage, "monster_zone": 2},
		"p1": {"hand": _hand(5)},
	})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_when_invading(0, 2, 3)

	assert_int(state.players[1].hand.size()) \
		.override_failure_message("ESD01-004: opponent hand with rage=%d" % rage) \
		.is_equal(expected_opp_hand)
	assert_int(state.players[1].discard_pile.size()).is_equal(5 - expected_opp_hand)


# --- ESD01-005 / ESD01-015: <Enter> — opponent discards down to N ---
# (enter triggers, not phase triggers — reclassify.)

func test_enter_discards_opponent_down_to(card_id: String, target_count: int,
		test_parameters := [
			["ESD01-005", 4],
			["ESD01-015", 2],
		]) -> void:
	var s := _setup(card_id, {"p1": {"hand": _hand(5)}})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].trigger_enter(0, s["card"])

	assert_int(state.players[1].hand.size()) \
		.override_failure_message("%s: opponent hand after enter" % card_id).is_equal(target_count)
	assert_int(state.players[1].discard_pile.size()).is_equal(5 - target_count)
	assert_int(input.count_calls("choose_hand_discards")).is_equal(1)
	assert_int(input.calls[0]["player_id"]).is_equal(1)


# --- Generic gating: phase-filtered cards must not fire in the wrong phase or
# with the wrong turn ownership, even on a board where the body WOULD act. ---

func test_phase_trigger_gating_blocks_wrong_phase_or_turn(card_id: String, zone_idx: int, monster_zone: int, phase: int, current_pid: int,
		test_parameters := [
			# card           zone  mz  wrong phase / turn combo
			["EBP01-001", -1, 1, CardEnums.GamePhase.MAIN, 0],     # right turn, wrong phase
			["EBP01-001", -1, 1, CardEnums.GamePhase.COUNTER, 1],  # right phase, wrong turn
			["EBP01-006", -1, 3, CardEnums.GamePhase.MAIN, 1],
			["EBP01-006", -1, 3, CardEnums.GamePhase.COUNTER, 0],
			["EBP02-036", 1, 1, CardEnums.GamePhase.MAIN, 0],
			["EBP02-036", 1, 1, CardEnums.GamePhase.END, 1],
			["EBP04-008", -1, 8, CardEnums.GamePhase.MAIN, 0],
			["EBP04-008", -1, 8, CardEnums.GamePhase.COUNTER, 1],
			["EBP02-001", -1, 1, CardEnums.GamePhase.MAIN, 1],
			["EBP02-001", -1, 1, CardEnums.GamePhase.COUNTER, 0],
			["EBP03-044", 2, 1, CardEnums.GamePhase.COUNTER, 0],
			["EBP03-044", 2, 1, CardEnums.GamePhase.MAIN, 1],
			["ESD02-007", 2, 1, CardEnums.GamePhase.COUNTER, 0],
			["ESD02-007", 2, 1, CardEnums.GamePhase.MAIN, 1],
			["ESD02-008", 2, 1, CardEnums.GamePhase.COUNTER, 0],
			["ESD02-008", 2, 1, CardEnums.GamePhase.MAIN, 1],
		]) -> void:
	var s := _setup(card_id, {
		"zone_idx": zone_idx,
		"current_player_id": current_pid,
		"phase": phase,
		"p0": {
			"monster_zone": monster_zone,
			"rage": 3,
			"hand": [Cards.strategy(2, "HAND-STR"), Cards.battle(2, 3000, "HAND-BTL")],
			"main_deck": [
				Cards.monster(2, 9000, [], "DECK-MON"),
				Real.instance("ESD02-010"),
				Real.instance("ESD02-011"),
				Cards.battle(1, 2000, "DECK-B"),
			],
		},
		"p1": {
			"monster_zone": 2,
			"hand": _hand(5),
			"zone_cards": {2: Cards.battle(5, 5000, "OPP-R5A"), 7: Cards.battle(5, 5000, "OPP-R5B")},
		},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]
	var snapshot_before := _snapshot(state)

	await s["effect_handler"].trigger_phase_start(state.current_phase)

	assert_that(_snapshot(state)) \
		.override_failure_message("%s: trigger fired in phase %d with current player %d" % [card_id, phase, current_pid]) \
		.is_equal(snapshot_before)
	assert_array(input.calls) \
		.override_failure_message("%s: prompts issued despite TRIGGER_FILTERS gating" % card_id) \
		.is_empty()
