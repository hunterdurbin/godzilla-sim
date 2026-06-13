extends GdUnitTestSuite

## Tier B cluster: cards in the on_rage_changed family (plus the related
## when_invading / enter / hand-discard / counter-success rage bodies the
## classification ledger grouped here), driven through the real seams:
## effect_handler.gain_rage / reduce_rage do the old/new rage bookkeeping and
## dispatch trigger_rage_changed → registry → TRIGGER_FILTERS (direction /
## own_turn) → standby resolution. Direction and turn gating get explicit
## negative coverage. See classification.md for cluster membership.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


## Place the real card on player 0's board per its card type (monster →
## current_monster, battle → zone opts.zone_idx, strategy → strategy zone 0)
## and return the wired session. opts: zone_idx, current_player_id,
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


## Rich board where every rage-increase watcher in this suite WOULD act:
## p0 monster_zone 6 (awakening6; column anchor idx 5 → opp column [0]),
## a fixture strategy in play (EBP02-005's condition), a millable deck with a
## monster on top (EBP01-003's follow-up), opponent hand of 5 and destroyable
## rank<=6 battle cards at idx 0 (column / same-zone target) and idx 3.
func _rich_setup(card_id: String, current_pid: int = 0) -> Dictionary:
	return _setup(card_id, {
		"current_player_id": current_pid,
		"p0": {
			"rage": 2,
			"monster_zone": 6,
			"main_deck": [Cards.monster(2, 9000, [], "DECK-MON"), Cards.battle(1, 2000, "DECK-B")],
			"strategy_zones": [Cards.strategy(2, "P0-STRAT")],
		},
		"p1": {
			"monster_zone": 2,
			"hand": _hand(5),
			"zone_cards": {0: Cards.battle(2, 3000, "OPP-Z1"), 3: Cards.battle(3, 4000, "OPP-Z4")},
		},
	})


# --- EBP01-003: rage increase — mill 1; destroy opp rank<=6 if a monster milled ---

func test_ebp01_003_rage_increase_mills_then_destroys_on_monster_mill(top_is_monster: bool, expect_destroy: bool,
		test_parameters := [
			[true, true],
			[false, false],
		]) -> void:
	var top := Cards.monster(2, 9000, [], "TOP-MON") if top_is_monster else Cards.battle(2, 3000, "TOP-BTL")
	var s := _setup("EBP01-003", {
		"p0": {"main_deck": [top, Cards.battle(1, 2000, "DECK-1")]},
		"p1": {"zone_cards": {3: Cards.battle(6, 5000, "OPP-R6")}},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].gain_rage(0, 1)

	assert_int(state.players[0].rage).is_equal(1)
	assert_int(state.players[0].main_deck.size()).is_equal(1)
	assert_int(state.players[0].discard_pile.size()).is_equal(1)
	assert_bool(state.players[1].zone_has_cards(3)) \
		.override_failure_message("EBP01-003: destroy only after milling a monster (milled %s)" % top["id"]) \
		.is_equal(not expect_destroy)
	assert_int(state.players[1].discard_pile.size()).is_equal(1 if expect_destroy else 0)
	assert_int(input.count_calls("select_zone")).is_equal(1 if expect_destroy else 0)


# --- EBP01-010: rage increase — destroy ALL opp battle cards in own column ---

func test_ebp01_010_rage_increase_destroys_all_in_monster_column() -> void:
	var s := _setup("EBP01-010", {
		"p0": {"monster_zone": 3},  # anchor idx 2 → opponent column zones [2, 7]
		"p1": {"zone_cards": {
			2: Cards.battle(7, 7000, "OPP-COL-A"),
			7: Cards.battle(2, 3000, "OPP-COL-B"),
			4: Cards.battle(2, 3000, "OPP-BYSTANDER"),
		}},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].gain_rage(0, 1)

	assert_bool(state.players[1].zone_has_cards(2)).is_false()
	assert_bool(state.players[1].zone_has_cards(7)).is_false()
	assert_bool(state.players[1].zone_has_cards(4)) \
		.override_failure_message("EBP01-010: out-of-column card must survive").is_true()
	assert_int(state.players[1].discard_pile.size()).is_equal(2)
	assert_int(input.count_calls("select_zone")).is_equal(0)  # whole column, no targeting


# --- EBP02-008: rage increase — destroy opp same-numbered zone if rank<=6 ---

func test_ebp02_008_rage_increase_destroys_same_numbered_zone(opp_rank: int, expect_destroy: bool,
		test_parameters := [
			[6, true],
			[7, false],
		]) -> void:
	var s := _setup("EBP02-008", {
		"p0": {"monster_zone": 3},  # same-numbered zone → opponent idx 2
		"p1": {"zone_cards": {2: Cards.battle(opp_rank, 5000, "OPP-SAME-ZONE")}},
	})
	var state: GameState = s["state"]

	await s["effect_handler"].gain_rage(0, 1)

	assert_bool(state.players[1].zone_has_cards(2)) \
		.override_failure_message("EBP02-008: opp_rank=%d" % opp_rank).is_equal(not expect_destroy)
	assert_int(state.players[1].discard_pile.size()).is_equal(1 if expect_destroy else 0)


# --- EBP02-005: own turn + rage increase + Awakening6 + strategy in play —
#     opponent discards to 3 ---

func test_ebp02_005_rage_increase_discards_opponent_when_awakened(monster_zone: int, has_strategy: bool, expected_opp_hand: int,
		test_parameters := [
			[6, true, 3],
			[5, true, 5],   # not awakened — body condition gates
			[6, false, 5],  # no strategy in play — body condition gates
		]) -> void:
	var p0_opts := {"monster_zone": monster_zone}
	if has_strategy:
		p0_opts["strategy_zones"] = [Cards.strategy(2, "P0-STRAT")]
	var s := _setup("EBP02-005", {"p0": p0_opts, "p1": {"hand": _hand(5)}})
	var state: GameState = s["state"]

	await s["effect_handler"].gain_rage(0, 1)

	assert_int(state.players[1].hand.size()) \
		.override_failure_message("EBP02-005: monster_zone=%d has_strategy=%s" % [monster_zone, has_strategy]) \
		.is_equal(expected_opp_hand)
	assert_int(state.players[1].discard_pile.size()).is_equal(5 - expected_opp_hand)


# --- ESD01-013: own turn + rage increase — destroy 1 opp rank<=6 battle card ---

func test_esd01_013_rage_increase_destroys_low_rank_target() -> void:
	var s := _setup("ESD01-013", {
		"p1": {"zone_cards": {3: Cards.battle(6, 5000, "OPP-R6"), 4: Cards.battle(7, 7000, "OPP-R7")}},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].gain_rage(0, 1)

	assert_int(input.count_calls("select_zone")).is_equal(1)
	assert_array(input.calls[0]["valid"]) \
		.override_failure_message("ESD01-013: only rank<=6 zones are valid targets") \
		.contains_exactly([3])
	assert_bool(state.players[1].zone_has_cards(3)).is_false()
	assert_bool(state.players[1].zone_has_cards(4)).is_true()
	assert_int(state.players[1].discard_pile.size()).is_equal(1)


# --- Direction gating: "increase"-filtered watchers must NOT fire on a
#     rage decrease driven through the real reduce_rage bookkeeping. ---

func test_rage_decrease_does_not_fire_increase_watchers(card_id: String,
		test_parameters := [
			["EBP01-003"],
			["EBP01-010"],
			["EBP02-008"],
			["EBP02-005"],
			["ESD01-013"],
		]) -> void:
	var s := _rich_setup(card_id)
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]
	var snapshot_before := _snapshot(state)

	await s["effect_handler"].reduce_rage(0, 1)

	assert_int(state.players[0].rage).is_equal(1)  # the reduction itself happened
	snapshot_before["p0"]["rage"] = 1  # the only sanctioned change
	assert_that(_snapshot(state)) \
		.override_failure_message("%s: increase-filtered trigger fired on reduce_rage" % card_id) \
		.is_equal(snapshot_before)
	assert_array(input.calls) \
		.override_failure_message("%s: prompts issued despite direction gating" % card_id) \
		.is_empty()


# --- Turn gating: own_turn-filtered rage watchers must NOT fire when the
#     owner's rage increases during the opponent's turn. ---

func test_own_turn_rage_watchers_skip_opponent_turn(card_id: String,
		test_parameters := [
			["EBP02-005"],
			["ESD01-013"],
		]) -> void:
	var s := _rich_setup(card_id, 1)
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]
	var snapshot_before := _snapshot(state)

	await s["effect_handler"].gain_rage(0, 1)

	snapshot_before["p0"]["rage"] = 3  # the gain itself is the only sanctioned change
	assert_that(_snapshot(state)) \
		.override_failure_message("%s: own_turn trigger fired on the opponent's turn" % card_id) \
		.is_equal(snapshot_before)
	assert_array(input.calls) \
		.override_failure_message("%s: prompts issued despite own_turn gating" % card_id) \
		.is_empty()


# --- EBP01-009: <When Invading> + rage>=2 — destroy 1 opp rank<=6 ---
# (when_invading trigger, not a rage trigger — reclassify.)

func test_ebp01_009_when_invading_destroys_if_two_rage(rage: int, expect_destroy: bool,
		test_parameters := [
			[2, true],
			[1, false],
		]) -> void:
	var s := _setup("EBP01-009", {
		"p0": {"rage": rage, "monster_zone": 3},
		"p1": {"zone_cards": {3: Cards.battle(6, 5000, "OPP-R6")}},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].trigger_when_invading(0, 2, 3)

	assert_bool(state.players[1].zone_has_cards(3)) \
		.override_failure_message("EBP01-009: rage=%d" % rage).is_equal(not expect_destroy)
	assert_int(state.players[1].discard_pile.size()).is_equal(1 if expect_destroy else 0)
	assert_int(input.count_calls("select_zone")).is_equal(1 if expect_destroy else 0)


# --- ESD02-005: <When Invading> — reduce opponent's rage by 1 ---
# (when_invading trigger, not a rage trigger — reclassify.)

func test_esd02_005_when_invading_reduces_opponent_rage() -> void:
	var s := _setup("ESD02-005", {
		"p0": {"monster_zone": 2},
		"p1": {"rage": 2},
	})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_when_invading(0, 1, 2)

	assert_int(state.players[1].rage).is_equal(1)


# --- EBP01-007: <When Invading> — reduce opp rage 2 when the invaded zone had
#     an own battle card (crush). Uses the deferred collect path because the
#     zone_had_card metadata is captured at collection time. ---
# (when_invading trigger, not a rage trigger — reclassify.)

func test_ebp01_007_when_invading_reduces_rage_when_invaded_zone_had_card(zone_occupied: bool, expected_opp_rage: int,
		test_parameters := [
			[true, 1],
			[false, 3],
		]) -> void:
	var p0_opts := {"monster_zone": 3}
	if zone_occupied:
		p0_opts["zone_cards"] = {2: Cards.battle(2, 3000, "OWN-CRUSHED")}
	var s := _setup("EBP01-007", {"p0": p0_opts, "p1": {"rage": 3}})
	var state: GameState = s["state"]
	var handler: EffectHandler = s["effect_handler"]

	var entries: Array = handler.collect_when_invading_entries(0, 2, 3)
	assert_int(entries.size()).is_equal(1)
	await handler.resolve_deferred_entries(entries)

	assert_int(state.players[1].rage) \
		.override_failure_message("EBP01-007: zone_occupied=%s" % zone_occupied) \
		.is_equal(expected_opp_rage)


# --- EBP02-T01: <Enter> — reduce opponent's rage by 1 ---
# (enter trigger, not a rage trigger — ledger already notes this; reclassify.)

func test_ebp02_t01_enter_reduces_opponent_rage(opp_rage: int, expected_opp_rage: int,
		test_parameters := [
			[2, 1],
			[0, 0],  # no rage to reduce — no underflow
		]) -> void:
	var s := _setup("EBP02-T01", {"zone_idx": 2, "p1": {"rage": opp_rage}})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_enter(0, s["card"])

	assert_int(state.players[1].rage).is_equal(expected_opp_rage)


# --- EBP03-015 / EBP03-016: hand battle card discarded — reduce opp rage 1
#     (016 gains own rage instead when the opponent has none) ---

func test_hand_battle_discarded_adjusts_rage(card_id: String, opp_rage: int, expected_opp_rage: int, expected_own_rage: int,
		test_parameters := [
			["EBP03-015", 2, 1, 0],
			["EBP03-016", 2, 1, 0],
			["EBP03-016", 0, 0, 1],  # opponent at 0 — gain own rage instead
		]) -> void:
	var s := _setup(card_id, {"p1": {"rage": opp_rage}})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_hand_card_discarded(0, Cards.battle(2, 3000, "DISCARDED-BTL"))

	assert_int(state.players[1].rage) \
		.override_failure_message("%s: opponent rage (started at %d)" % [card_id, opp_rage]) \
		.is_equal(expected_opp_rage)
	assert_int(state.players[0].rage).is_equal(expected_own_rage)


func test_hand_discard_card_type_filter_ignores_non_battle(card_id: String,
		test_parameters := [
			["EBP03-015"],
			["EBP03-016"],
		]) -> void:
	var s := _setup(card_id, {"p1": {"rage": 2}})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_hand_card_discarded(0, Cards.strategy(2, "DISCARDED-STR"))

	assert_int(state.players[1].rage) \
		.override_failure_message("%s: card_type=battle filter must skip strategy discards" % card_id) \
		.is_equal(2)
	assert_int(state.players[0].rage).is_equal(0)


# --- EBP03-019: counter success with a <Base> in play — gain 2 rage ---
# (on_counter_success trigger, not a rage trigger — reclassify.)

func test_ebp03_019_counter_success_gains_rage_with_base(has_base: bool, expected_rage: int,
		test_parameters := [
			[true, 2],
			[false, 0],
		]) -> void:
	var p0_opts := {}
	if has_base:
		var base := Cards.strategy(2, "BASE-STRAT")
		base["is_base"] = true
		p0_opts["strategy_zones"] = [base]
	var s := _setup("EBP03-019", {"p0": p0_opts})
	var state: GameState = s["state"]

	await s["effect_handler"].trigger_counter_success(0, 1)

	assert_int(state.players[0].rage) \
		.override_failure_message("EBP03-019: has_base=%s" % has_base).is_equal(expected_rage)


# --- EBP01-076: own-turn invasion observed — destroy 1 opp battle card ---
# (on_invasion_observed trigger, not a rage trigger — reclassify.)

func test_ebp01_076_invasion_observed_destroys_only_on_own_turn(current_pid: int, expect_destroy: bool,
		test_parameters := [
			[0, true],
			[1, false],
		]) -> void:
	var s := _setup("EBP01-076", {
		"current_player_id": current_pid,
		"p1": {"zone_cards": {3: Cards.battle(4, 4000, "OPP-TARGET")}},
	})
	var state: GameState = s["state"]
	var input: ScriptedPlayerInput = s["input"]

	await s["effect_handler"].trigger_invasion_observed(0, 2, 3)

	assert_bool(state.players[1].zone_has_cards(3)) \
		.override_failure_message("EBP01-076: current_pid=%d" % current_pid).is_equal(not expect_destroy)
	assert_int(state.players[1].discard_pile.size()).is_equal(1 if expect_destroy else 0)
	assert_int(input.count_calls("select_zone")).is_equal(1 if expect_destroy else 0)
