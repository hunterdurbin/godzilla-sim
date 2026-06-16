extends GdUnitTestSuite

## Tier B cluster: stat_modifier cards whose passive getters cover the
## non-CP query surfaces — threat level, engagement restriction, play-rank
## modifiers, counter immunity/prevention, blocking getters, destruction
## protection, and strategy-hand rank modifiers. Everything is asserted
## through the EffectQueries/DestructionEngine aggregation layer, never by
## calling the effect's getter directly, and every scenario asserts both the
## firing and the non-firing state. See classification.md for membership.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")


func _wire(state: GameState) -> EffectHandler:
	return States.make_session(state)["effect_handler"]


func _battle_colored(color: int, id: String, rank: int = 2, cp: int = 3000) -> Dictionary:
	var card := Cards.battle(rank, cp, id)
	card["colors"] = [color]
	return card


## A Crystals token as the engine creates it (bare template id, TOKEN trait).
func _crystal(copy: int) -> Dictionary:
	var token := Real.instance("EBP02-T03", copy)
	token["id"] = "EBP02-T03"
	return token


# --- Threat level modifiers (get_effective_threat_level) ---


## Build the FIRING state for each threat-modifier card; returns
## {"state": GameState, "handler": EffectHandler}.
func _threat_setup(card_id: String) -> Dictionary:
	var state: GameState
	match card_id:
		"EBP02-002":  # +5000 with any own strategy in play
			state = States.make_state({"p0": {
				"current_monster": Real.instance(card_id),
				"strategy_zones": [Cards.strategy(2, "STR-A")],
			}})
		"EBP02-045":  # +3000 per opp monster rank (rank 3 → +9000)
			state = States.make_state({
				"p0": {"current_monster": Real.instance(card_id)},
				"p1": {"current_monster": Cards.monster(3)},
			})
		"EBP02-051":  # 5+ under → +3000 per opp unoccupied zone (7 here)
			state = States.make_state({"p0": {"current_monster": Real.instance(card_id)}})
			for i in range(5):
				state.players[0].monster_stack.append(
					Cards.monster(1, 5000, [CardEnums.CardTrait.KING_GHIDORAH], "STK-%d" % i))
		"EBP02-T03":  # each Crystal grants +1000 TL to a SpaceGodzilla monster
			state = States.make_state({"p0": {
				"current_monster": Cards.monster(1, 5000, [CardEnums.CardTrait.SPACEGODZILLA], "SG-MON"),
				"zone_cards": {0: _crystal(0), 1: _crystal(1)},
			}})
		"EBP03-022":  # +10000 with a <Base> strategy in play
			var base_strat := Cards.strategy(4, "T-BASE")
			base_strat["is_base"] = true
			state = States.make_state({"p0": {
				"current_monster": Real.instance(card_id),
				"strategy_zones": [base_strat],
			}})
		"EBP03-076":  # opp turn: +5000 per own monster/battle card in zones 1, 5, 8
			state = States.make_state({
				"current_player_id": 1,
				"p0": {
					"strategy_zones": [Real.instance(card_id)],
					"monster_zone": 8,
					"zone_cards": {0: Cards.battle(2, 3000, "Z1"), 4: Cards.battle(2, 3000, "Z5")},
				},
			})
		"EBP04-011":  # red + blue battle in zones → +10000
			state = States.make_state({"p0": {
				"current_monster": Real.instance(card_id),
				"zone_cards": {
					0: _battle_colored(CardEnums.CardColor.RED, "RED-1"),
					1: _battle_colored(CardEnums.CardColor.BLUE, "BLUE-1"),
				},
			}})
		"EBP04-016":  # own monster zone >= opp monster zone → +3000
			state = States.make_state({
				"p0": {"current_monster": Real.instance(card_id), "monster_zone": 3},
				"p1": {"monster_zone": 2},
			})
		"EBP04-019":  # zone >= opp zone AND 5+ monsters in discard → +10000
			state = States.make_state({
				"p0": {"current_monster": Real.instance(card_id), "monster_zone": 4},
			})
			for i in range(5):
				state.players[0].discard_pile.append(
					Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "DIS-M%d" % i))
		"EBP04-023":  # +10000 per opp battle card in own monster's column
			# Monster at zone 3 (idx 2) → opp column zones idx 2 and 7.
			state = States.make_state({
				"p0": {"current_monster": Real.instance(card_id), "monster_zone": 3},
				"p1": {"zone_cards": {2: Cards.battle(2, 3000, "OPP-A"), 7: Cards.battle(2, 3000, "OPP-B")}},
			})
		"EBP04-031", "EBP04-032":  # threat = N per distinct battle color in own zones
			state = States.make_state({"p0": {
				"current_monster": Real.instance(card_id),
				"zone_cards": {
					0: _battle_colored(CardEnums.CardColor.RED, "RED-1"),
					1: _battle_colored(CardEnums.CardColor.BLUE, "BLUE-1"),
				},
			}})
		"EBP04-036":  # +5000 per distinct battle color in own discard
			state = States.make_state({"p0": {"current_monster": Real.instance(card_id)}})
			state.players[0].discard_pile.append(_battle_colored(CardEnums.CardColor.RED, "D-RED"))
			state.players[0].discard_pile.append(_battle_colored(CardEnums.CardColor.BLUE, "D-BLUE"))
			state.players[0].discard_pile.append(_battle_colored(CardEnums.CardColor.GREEN, "D-GREEN"))
		"ESD01-003":  # rage >= 2 → +5000
			state = States.make_state({"p0": {"current_monster": Real.instance(card_id), "rage": 2}})
		"ESD02-006":  # +5000 per opp strategy in play
			state = States.make_state({
				"p0": {"current_monster": Real.instance(card_id)},
				"p1": {"strategy_zones": [Cards.strategy(1, "OPP-S1"), Cards.strategy(2, "OPP-S2")]},
			})
	return {"state": state, "handler": _wire(state)}


## Flip the condition that made the card fire.
func _threat_break(card_id: String, state: GameState) -> void:
	match card_id:
		"EBP02-002":
			state.players[0].strategy_zones[0] = {}
		"EBP02-045":
			state.players[1].current_monster = Cards.monster(1)
		"EBP02-051":
			state.players[0].monster_stack.resize(4)
		"EBP02-T03":
			state.players[0].current_monster = Cards.monster()  # GODZILLA, not SpaceGodzilla
		"EBP03-022":
			state.players[0].strategy_zones[0]["is_base"] = false
		"EBP03-076":
			state.current_player_id = 0
		"EBP04-011":
			state.players[0].clear_zone(1)  # blue gone, red only
		"EBP04-016":
			state.players[0].monster_zone = 1
		"EBP04-019":
			state.players[0].discard_pile.pop_back()
		"EBP04-023":
			state.players[1].clear_zone(2)
			state.players[1].clear_zone(7)
		"EBP04-031", "EBP04-032":
			state.players[0].clear_zone(0)
			state.players[0].clear_zone(1)
		"EBP04-036":
			state.players[0].discard_pile.clear()
		"ESD01-003":
			state.players[0].rage = 1
		"ESD02-006":
			state.players[1].strategy_zones[0] = {}
			state.players[1].strategy_zones[1] = {}


func test_threat_level_modifier(card_id: String, firing_bonus: int, broken_bonus: int,
		test_parameters := [
			["EBP02-002", 5000, 0],
			["EBP02-045", 9000, 3000],  # scales with opp monster rank, never fully off
			["EBP02-051", 21000, 0],
			["EBP02-T03", 2000, 0],
			["EBP03-022", 10000, 0],
			["EBP03-076", 15000, 0],
			["EBP04-011", 10000, 0],
			["EBP04-016", 3000, 0],
			["EBP04-019", 10000, 0],
			["EBP04-023", 20000, 0],
			["EBP04-031", 6000, 0],
			["EBP04-032", 20000, 0],
			["EBP04-036", 15000, 0],
			["ESD01-003", 5000, 0],
			["ESD02-006", 10000, 0],
		]) -> void:
	var s := _threat_setup(card_id)
	var state: GameState = s["state"]
	var handler: EffectHandler = s["handler"]

	assert_int(handler.get_effective_threat_level(0)) \
		.override_failure_message("%s: threat bonus %d while condition holds" % [card_id, firing_bonus]) \
		.is_equal(state.players[0].get_threat_level() + firing_bonus)

	_threat_break(card_id, state)
	assert_int(handler.get_effective_threat_level(0)) \
		.override_failure_message("%s: threat bonus %d after condition broken" % [card_id, broken_bonus]) \
		.is_equal(state.players[0].get_threat_level() + broken_bonus)


# --- Engagement restriction (get_engagement_restriction, counter phase only) ---


func test_engagement_restriction(card_id: String, restricted_rank: int,
		test_parameters := [
			["EBP01-014", 5],  # opp turn + Awakening4 + 2 own battle cards
			["EBP01-028", 3],  # strategy, opp turn
			["EBP04-006", 5],  # opp turn + 3 rank-1 strategies in discard
		]) -> void:
	var state: GameState
	match card_id:
		"EBP01-014":
			state = States.make_state({
				"current_player_id": 1,
				"p0": {
					"current_monster": Real.instance(card_id),
					"monster_zone": 4,
					"zone_cards": {0: Cards.battle(2, 3000, "B-0"), 1: Cards.battle(2, 3000, "B-1")},
				},
			})
		"EBP01-028":
			state = States.make_state({
				"current_player_id": 1,
				"p0": {"strategy_zones": [Real.instance(card_id)]},
			})
		"EBP04-006":
			state = States.make_state({
				"current_player_id": 1,
				"p0": {"current_monster": Real.instance(card_id)},
			})
			for i in range(3):
				state.players[0].discard_pile.append(Cards.strategy(1, "DIS-S%d" % i))
	state.current_phase = CardEnums.GamePhase.COUNTER
	var handler := _wire(state)

	assert_int(handler.get_engagement_restriction(0)) \
		.override_failure_message("%s: restricts rank <= %d during opp counter phase" % [card_id, restricted_rank]) \
		.is_equal(restricted_rank)

	# Restriction only exists during the counter phase.
	state.current_phase = CardEnums.GamePhase.MAIN
	assert_int(handler.get_engagement_restriction(0)).is_equal(-1)
	state.current_phase = CardEnums.GamePhase.COUNTER

	# All three are <Opponent's Turn> effects.
	state.current_player_id = 0
	assert_int(handler.get_engagement_restriction(0)) \
		.override_failure_message("%s: no restriction on own turn" % card_id) \
		.is_equal(-1)
	state.current_player_id = 1

	# Card-specific condition break.
	match card_id:
		"EBP01-014":
			state.players[0].clear_zone(1)  # only 1 battle card left
		"EBP01-028":
			state.players[0].strategy_zones[0] = {}
		"EBP04-006":
			state.players[0].discard_pile.pop_back()  # only 2 rank-1 strategies
	assert_int(handler.get_engagement_restriction(0)) \
		.override_failure_message("%s: no restriction once condition is broken" % card_id) \
		.is_equal(-1)


# --- Play rank modifiers (get_play_rank_modifier) ---


func test_play_rank_self_per_own_battle_ebp01_027() -> void:
	var card := Real.instance("EBP01-027")
	var state := States.make_state({"p0": {"zone_cards": {
		0: Cards.battle(2, 3000, "B-0"),
		1: Cards.battle(2, 3000, "B-1"),
	}}})
	var handler := _wire(state)

	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-2)

	state.players[0].clear_zone(0)
	state.players[0].clear_zone(1)
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


func test_play_rank_self_awakening_nonred_ebp04_044() -> void:
	var card := Real.instance("EBP04-044")
	var state := States.make_state({"p0": {
		"monster_zone": 4,
		"zone_cards": {
			0: _battle_colored(CardEnums.CardColor.BLUE, "BLUE-1"),
			1: _battle_colored(CardEnums.CardColor.GREEN, "GREEN-1"),
		},
	}})
	var handler := _wire(state)

	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-4)

	# Below Awakening4 the reduction is off even with non-red cards in zones.
	state.players[0].monster_zone = 3
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)

	# Red battle cards do not count.
	state.players[0].monster_zone = 4
	state.players[0].clear_zone(0)
	state.players[0].clear_zone(1)
	state.players[0].push_zone_card(0, _battle_colored(CardEnums.CardColor.RED, "RED-1"))
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


func test_play_rank_self_per_opp_battle_efc01_004() -> void:
	var card := Real.instance("EFC01-004")
	var state := States.make_state({"p1": {"zone_cards": {
		0: Cards.battle(2, 3000, "O-0"),
		1: Cards.battle(2, 3000, "O-1"),
		2: Cards.battle(2, 3000, "O-2"),
	}}})
	var handler := _wire(state)

	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(-3)

	for i in range(3):
		state.players[1].clear_zone(i)
	assert_int(handler.get_play_rank_modifier(0, card)).is_equal(0)


func test_play_rank_strategy_biollante_ebp02_039() -> void:
	var state := States.make_state({"p0": {"strategy_zones": [Real.instance("EBP02-039")]}})
	var handler := _wire(state)
	var biollante := Cards.battle(6, 4000, "BIO-1", [CardEnums.CardTrait.BIOLLANTE])

	assert_int(handler.get_play_rank_modifier(0, biollante)) \
		.override_failure_message("EBP02-039: Biollante battle cards cost -3 rank on own turn") \
		.is_equal(-3)

	# Non-Biollante battle card unaffected.
	assert_int(handler.get_play_rank_modifier(0, Cards.battle(6, 4000, "PLAIN"))).is_equal(0)

	# <Your Turn> only.
	state.current_player_id = 1
	assert_int(handler.get_play_rank_modifier(0, biollante)).is_equal(0)


# --- Counter immunity (get_counter_immunity_threshold) ---


func test_counter_immunity(card_id: String, threshold: int,
		test_parameters := [
			["EBP01-038", 50000],  # opp turn + Awakening6
			["EBP02-027", 40000],  # opp turn + Awakening6 + opp strategy in play
		]) -> void:
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": Real.instance(card_id), "monster_zone": 6},
		"p1": {"strategy_zones": [Cards.strategy(2, "OPP-S")]},
	})
	var handler := _wire(state)

	assert_int(handler.get_counter_immunity_threshold(0)) \
		.override_failure_message("%s: immunity threshold while condition holds" % card_id) \
		.is_equal(threshold)

	# <Opponent's Turn> only.
	state.current_player_id = 0
	assert_int(handler.get_counter_immunity_threshold(0)).is_equal(0)
	state.current_player_id = 1

	# Card-specific condition break.
	match card_id:
		"EBP01-038":
			state.players[0].monster_zone = 5  # below Awakening6
		"EBP02-027":
			state.players[1].strategy_zones[0] = {}
	assert_int(handler.get_counter_immunity_threshold(0)) \
		.override_failure_message("%s: no immunity once condition is broken" % card_id) \
		.is_equal(0)


# --- Counter prevention (is_counter_prevented) ---


func test_counter_prevented_low_opp_presence(card_id: String,
		test_parameters := [
			["EBP04-031"],
			["EBP04-032"],
		]) -> void:
	var state := States.make_state({
		"p0": {"current_monster": Real.instance(card_id)},
		"p1": {"zone_cards": {0: Cards.battle(2, 3000, "O-0")}},
	})
	var handler := _wire(state)

	# Opponent has 1 battle card (<= 1) → counter fully prevented at any CP.
	assert_bool(handler.is_counter_prevented(0, 100000)) \
		.override_failure_message("%s: counter prevented with <=1 opp battle card" % card_id) \
		.is_true()

	state.players[1].push_zone_card(1, Cards.battle(2, 3000, "O-1"))
	assert_bool(handler.is_counter_prevented(0, 100000)) \
		.override_failure_message("%s: counter allowed with 2 opp battle cards" % card_id) \
		.is_false()


# --- Blocking getters ---


func test_monster_cannot_advance_or_invade_ebp02_024() -> void:
	var state := States.make_state({"p0": {"current_monster": Real.instance("EBP02-024")}})
	var handler := _wire(state)

	assert_bool(handler.is_monster_advance_blocked(0)).is_true()
	assert_bool(handler.is_own_invasion_blocked(0)).is_true()
	# The other player's plain monster is not affected.
	assert_bool(handler.is_monster_advance_blocked(1)).is_false()
	assert_bool(handler.is_own_invasion_blocked(1)).is_false()


func test_strategy_blocks_advance_invade_own_turn_ebp04_081() -> void:
	var state := States.make_state({"p0": {"strategy_zones": [Real.instance("EBP04-081")]}})
	var handler := _wire(state)

	# <Your Turn> (current_player_id defaults to 0).
	assert_bool(handler.is_monster_advance_blocked(0)).is_true()
	assert_bool(handler.is_own_invasion_blocked(0)).is_true()

	state.current_player_id = 1
	assert_bool(handler.is_monster_advance_blocked(0)).is_false()
	assert_bool(handler.is_own_invasion_blocked(0)).is_false()


func test_blocked_opponent_zones_crystals_ebp02_055() -> void:
	# Monster at zone 4 (idx 3) → blocks the opponent's column-4 zone (idx 1).
	var state := States.make_state({"p0": {
		"current_monster": Real.instance("EBP02-055"),
		"monster_zone": 4,
		"zone_cards": {0: _crystal(0), 1: _crystal(1), 2: _crystal(2)},
	}})
	var handler := _wire(state)

	assert_array(handler.get_opponent_blocked_zones(0)) \
		.override_failure_message("EBP02-055: blocks opp zones in the monster's column") \
		.contains_exactly([1])

	# Only 2 Crystals → no blocking.
	state.players[0].clear_zone(2)
	assert_array(handler.get_opponent_blocked_zones(0)).is_empty()

	# 3 Crystals but below Awakening4 → no blocking.
	state.players[0].push_zone_card(2, _crystal(3))
	state.players[0].monster_zone = 3
	assert_array(handler.get_opponent_blocked_zones(0)).is_empty()


func test_invasion_blocked_column_rage0_ebp04_056() -> void:
	# Card at idx 2 (zone 3) faces opp zones 3/8 → opp monster at zone 3 is in column.
	var state := States.make_state({
		"p0": {"zone_cards": {2: Real.instance("EBP04-056")}},
		"p1": {"monster_zone": 3, "rage": 0},
	})
	var handler := _wire(state)

	assert_bool(handler.is_invasion_blocked(0)) \
		.override_failure_message("EBP04-056: opp cannot invade while in column and opp rage is 0") \
		.is_true()

	state.players[1].rage = 1
	assert_bool(handler.is_invasion_blocked(0)).is_false()

	state.players[1].rage = 0
	state.players[1].monster_zone = 1
	assert_bool(handler.is_invasion_blocked(0)).is_false()


# --- Destruction protection (can_destroy_card) ---


func test_can_be_destroyed_protection_ebp01_052() -> void:
	var card := Real.instance("EBP01-052")
	var state := States.make_state({"p0": {"zone_cards": {2: card}, "monster_zone": 4}})
	for i in range(5):
		state.players[0].discard_pile.append(Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "DIS-M%d" % i))
	var handler := _wire(state)
	var p0: PlayerState = state.players[0]

	# Opponent's effect is the destruction cause → protected.
	handler.exec.set_active(1, Cards.battle(1, 1000, "OPP-EFF"))
	assert_bool(handler.can_destroy_card(p0, card)) \
		.override_failure_message("EBP01-052: protected from opponent effects when condition holds") \
		.is_false()

	# Own effect → caused_by_opponent gate fails, card is destroyable.
	handler.exec.set_active(0, Cards.battle(1, 1000, "OWN-EFF"))
	assert_bool(handler.can_destroy_card(p0, card)).is_true()

	# Opponent effect but only 4 monsters in discard → destroyable.
	handler.exec.set_active(1, Cards.battle(1, 1000, "OPP-EFF"))
	p0.discard_pile.pop_back()
	assert_bool(handler.can_destroy_card(p0, card)).is_true()

	# Restore discard; below Awakening4 → destroyable.
	p0.discard_pile.append(Cards.monster(1, 5000, [CardEnums.CardTrait.GODZILLA], "DIS-M9"))
	p0.monster_zone = 3
	assert_bool(handler.can_destroy_card(p0, card)).is_true()
	handler.exec.clear_active()


func test_protects_own_strategies_ebp04_048() -> void:
	var strat := Cards.strategy(2, "PROT-S")
	var plain_battle := Cards.battle(2, 3000, "PLAIN-B")
	var state := States.make_state({"p0": {
		"zone_cards": {0: Real.instance("EBP04-048"), 1: plain_battle},
		"strategy_zones": [strat],
	}})
	var handler := _wire(state)
	var p0: PlayerState = state.players[0]

	# Opponent's effect destroying the strategy → protected.
	handler.exec.set_active(1, Cards.battle(1, 1000, "OPP-EFF"))
	assert_bool(handler.can_destroy_card(p0, strat)) \
		.override_failure_message("EBP04-048: own strategies protected from opponent effects") \
		.is_false()
	# Battle cards are not covered by the protection.
	assert_bool(handler.can_destroy_card(p0, plain_battle)).is_true()

	# Own effect → not protected.
	handler.exec.set_active(0, Cards.battle(1, 1000, "OWN-EFF"))
	assert_bool(handler.can_destroy_card(p0, strat)).is_true()
	handler.exec.clear_active()


func test_protects_battle_cards_opp_turn_efc01_006() -> void:
	var battle := Cards.battle(2, 3000, "MY-B")
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {
			"strategy_zones": [Real.instance("EFC01-006")],
			"zone_cards": {0: battle},
		},
	})
	var handler := _wire(state)
	var p0: PlayerState = state.players[0]

	# Opponent effect, opp turn, opponent has <= 2 battle cards → protected.
	handler.exec.set_active(1, Cards.battle(1, 1000, "OPP-EFF"))
	assert_bool(handler.can_destroy_card(p0, battle)) \
		.override_failure_message("EFC01-006: own battle cards protected on opp turn with <=2 opp battle cards") \
		.is_false()

	# Opponent has 3 battle cards → no protection.
	for i in range(3):
		state.players[1].push_zone_card(i, Cards.battle(2, 3000, "O-%d" % i))
	assert_bool(handler.can_destroy_card(p0, battle)).is_true()
	for i in range(3):
		state.players[1].clear_zone(i)

	# <Opponent's Turn> only — on the owner's turn the protection is off.
	state.current_player_id = 0
	assert_bool(handler.can_destroy_card(p0, battle)).is_true()
	state.current_player_id = 1

	# Own effect as the cause → not protected.
	handler.exec.set_active(0, Cards.battle(1, 1000, "OWN-EFF"))
	assert_bool(handler.can_destroy_card(p0, battle)).is_true()
	handler.exec.clear_active()


# --- Strategy-hand rank modifiers (get_strategy_hand_rank_modifier) ---


func test_strategy_hand_rank_opp_increase_ebp04_066() -> void:
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {
			0: Real.instance("EBP04-066"),
			1: _battle_colored(CardEnums.CardColor.RED, "RED-1"),
		}},
	})
	var handler := _wire(state)
	var strat := Cards.strategy(3, "OPP-HAND-S")

	# Opp turn + non-green battle in own zones → opp hand strategies +2 rank.
	assert_int(handler.get_strategy_hand_rank_modifier(1, strat)) \
		.override_failure_message("EBP04-066: opp hand strategies gain +2 rank") \
		.is_equal(2)

	# Does not touch the owner's own hand.
	assert_int(handler.get_strategy_hand_rank_modifier(0, strat)).is_equal(0)

	# <Opponent's Turn> only.
	state.current_player_id = 0
	assert_int(handler.get_strategy_hand_rank_modifier(1, strat)).is_equal(0)
	state.current_player_id = 1

	# Without a non-green battle card (the card itself is green) → off.
	state.players[0].clear_zone(1)
	assert_int(handler.get_strategy_hand_rank_modifier(1, strat)).is_equal(0)


func test_strategy_hand_rank_own_decrease_ebp04_068() -> void:
	var state := States.make_state({"p0": {"zone_cards": {0: Real.instance("EBP04-068")}}})
	state.players[0].discard_pile.append(_battle_colored(CardEnums.CardColor.RED, "D-RED"))
	state.players[0].discard_pile.append(_battle_colored(CardEnums.CardColor.BLUE, "D-BLUE"))
	var handler := _wire(state)
	var strat := Cards.strategy(4, "OWN-HAND-S")

	# Own turn, no strategies in play, 2 distinct battle colors in discard → -2.
	assert_int(handler.get_strategy_hand_rank_modifier(0, strat)) \
		.override_failure_message("EBP04-068: own hand strategies gain -1 rank per discard color") \
		.is_equal(-2)

	# Non-strategy cards are unaffected.
	assert_int(handler.get_strategy_hand_rank_modifier(0, Cards.battle(4, 3000, "HB"))).is_equal(0)

	# A strategy in play turns it off.
	state.players[0].strategy_zones[0] = Cards.strategy(2, "IN-PLAY")
	assert_int(handler.get_strategy_hand_rank_modifier(0, strat)).is_equal(0)
	state.players[0].strategy_zones[0] = {}

	# <Your Turn> only.
	state.current_player_id = 1
	assert_int(handler.get_strategy_hand_rank_modifier(0, strat)).is_equal(0)
