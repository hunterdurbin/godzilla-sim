extends GdUnitTestSuite

## Effect plays and the "when played" watchers, with the real cards, driven
## through the effect-play primitives (play from hand / deck / discard, a
## token, Evolve). The Japanese rules use one verb, 出現, for every one of
## them (5.11 "play", 5.11.4 "play a token", 5.17.1 Evolve "重ねて出現させます"
## — comprehensive_rules/rules-ja.txt), and so do the cards:
##   - EBP02-073 "あなたの交戦カードが出現するたび" fires for every play;
##   - EBP04-028 / EBP04-072 "相手が山札から交戦カードを出現させるたび" fire
##     for deck plays: an effect playing from the deck (Q530) and Evolve
##     (Q176: "山札から…重ねて出現させる");
##   - EBP02-055 "交戦カードを出現させることができない" refuses every effect
##     play, Evolve included (Q270: "この効果は【進化】などのカードの効果による
##     出現も「できない」のですか？ A: はい、そうです。");
##   - a stack-on-play card (Godzilla Jr.) stacks through an effect play too.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")

const Source := EnterZone.Source

const TOKEN_ID := "EBP02-T03"  # Crystals, a battle token
const EVO_TRAIT := CardEnums.CardTrait.MOTHRA


func _session(state: GameState, input: ScriptedPlayerInput = null) -> Dictionary:
	var s := States.make_session(state, input)
	s["state"] = state
	return s


func _teardown(s: Dictionary) -> void:
	var ah: ActionHandler = s["action_handler"]
	ah.teardown()
	var handler: EffectHandler = s["effect_handler"]
	handler.teardown()


## `pid` plays a battle card into `zone` from `from` through the engine
## primitive, then the check timing resolves. Returns whether it was played.
## Evolve: an Evolution card is put in `zone` first and the played card
## waits in the deck for the search.
func _play(s: Dictionary, pid: int, from: Source, zone: int, card: Dictionary = {}) -> bool:
	var handler: EffectHandler = s["effect_handler"]
	var player: PlayerState = s["state"].players[pid]
	if card.is_empty():
		card = Cards.battle(3, 3000, "PLAYED", [EVO_TRAIT])
	var played := false
	match from:
		Source.HAND:
			player.hand.append(card)
			played = handler.play_battle_card_from_hand(pid, card, zone)
		Source.DECK:
			played = handler.play_battle_card_from_deck(pid, card, zone)
		Source.DISCARD:
			player.discard_pile.append(card)
			played = await handler.play_from_discard(pid, card, zone) == zone
		Source.TOKEN:
			played = handler.create_token_in_zone(player, TOKEN_ID, zone)
		Source.EVOLUTION:
			var base := Cards.battle(2, 2000, "BASE")
			base["evolution_rank"] = 5
			base["evolution_trait"] = EVO_TRAIT
			player.push_zone_card(zone, base)
			player.main_deck.append(card)
			played = await handler.perform_evolution(pid, zone)
	await handler.check_timing.resolve()
	return played


# --- EBP02-073 Bloody Chainsaw: "あなたの交戦カードが出現するたび" ---

@warning_ignore("unused_parameter")
func test_ebp02_073_fires_for_every_play(from: int,
		test_parameters := [
			[Source.HAND],
			[Source.DECK],
			[Source.DISCARD],
			[Source.TOKEN],
			[Source.EVOLUTION],
		]) -> void:
	var state := States.make_state({
		"p0": {"strategy_zones": [Real.instance("EBP02-073")]},
		"p1": {"zone_cards": {2: Cards.battle(6, 5000, "OPP-R6")}},
	})
	var s := _session(state)

	assert_bool(await _play(s, 0, from, 2)).is_true()

	# Column idx 2 → the opponent's zone idx 2 holds a rank 6 card.
	assert_bool(state.players[1].zone_has_cards(2)) \
		.override_failure_message("EBP02-073 from %s" % Source.keys()[from]) \
		.is_false()
	_teardown(s)


# --- EBP04-028 Gigan(2004): "相手が山札から交戦カードを出現させるたび" (Q530) ---

@warning_ignore("unused_parameter")
func test_ebp04_028_fires_only_for_a_deck_play(from: int, expect_fire: bool,
		test_parameters := [
			[Source.HAND, false],
			[Source.DECK, true],
			[Source.DISCARD, false],
			[Source.TOKEN, false],
			[Source.EVOLUTION, true],
		]) -> void:
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"current_monster": Real.instance("EBP04-028")},
		"p1": {"hand": [Cards.battle(1, 1000, "H1"), Cards.battle(1, 1000, "H2")]},
	})
	var s := _session(state)

	assert_bool(await _play(s, 1, from, 2)).is_true()

	assert_int(state.players[1].hand.size()) \
		.override_failure_message("EBP04-028 from %s" % Source.keys()[from]) \
		.is_equal(1 if expect_fire else 2)
	_teardown(s)


# --- EBP04-072 Sanda: "相手が山札から交戦カードを出現させるたび" (Q530) ---

@warning_ignore("unused_parameter")
func test_ebp04_072_fires_only_for_a_deck_play(from: int, expect_fire: bool,
		test_parameters := [
			[Source.HAND, false],
			[Source.DECK, true],
			[Source.DISCARD, false],
			[Source.TOKEN, false],
			[Source.EVOLUTION, true],
		]) -> void:
	var state := States.make_state({
		"current_player_id": 1,
		"p0": {"zone_cards": {4: Real.instance("EBP04-072")},
				"main_deck": [Cards.battle(2, 2000, "W1")]},
	})
	var input := ScriptedPlayerInput.new()
	var s := _session(state, input)

	assert_bool(await _play(s, 1, from, 2)).is_true()

	var sanda_searches := input.calls.filter(func(c: Dictionary) -> bool:
		return c["kind"] == "search_cards" and c["player_id"] == 0)
	assert_int(sanda_searches.size()) \
		.override_failure_message("EBP04-072 from %s" % Source.keys()[from]) \
		.is_equal(1 if expect_fire else 0)
	_teardown(s)


# --- EBP02-055 SpaceGodzilla: "相手は…交戦カードを出現させることができない" (Q270) ---

## p1's SpaceGodzilla at zone 4 with 3 Crystals blocks p0's zone idx 1.
func _spacegodzilla_state() -> GameState:
	var crystals := {}
	for i in range(3):
		crystals[5 + i] = Real.instance(TOKEN_ID, i)
	return States.make_state({"p1": {
		"current_monster": Real.instance("EBP02-055"),
		"monster_zone": 4,
		"zone_cards": crystals,
	}})


@warning_ignore("unused_parameter")
func test_ebp02_055_blocks_an_effect_play(from: int,
		test_parameters := [
			[Source.HAND],
			[Source.DECK],
			[Source.DISCARD],
			[Source.TOKEN],
			[Source.EVOLUTION],
		]) -> void:
	var state := _spacegodzilla_state()
	var input := ScriptedPlayerInput.new()
	var s := _session(state, input)
	var handler: EffectHandler = s["effect_handler"]
	var blocked: Array[int] = [1]
	assert_array(handler.get_opponent_blocked_zones(1)).is_equal(blocked)

	assert_bool(await _play(s, 0, from, 1)) \
		.override_failure_message("EBP02-055 vs %s" % Source.keys()[from]).is_false()

	# Nothing was played there (Evolve leaves its base card alone and never
	# searches the deck).
	var top: Dictionary = state.players[0].get_zone_top_card(1)
	assert_bool(top.get("id", "") in ["", "BASE"]).is_true()
	assert_int(input.count_calls("search_cards")).is_equal(0)
	assert_bool(handler.can_play_in_zone(0, 1)).is_false()
	assert_bool(handler.can_play_in_zone(0, 2)).is_true()
	_teardown(s)


# --- EBP03-051 Godzilla Jr.: stacks on Little Godzilla when played by an effect ---

@warning_ignore("unused_parameter")
func test_ebp03_051_stacks_on_little_godzilla_through_an_effect_play(from: int,
		test_parameters := [
			[Source.HAND],
			[Source.DECK],
			[Source.DISCARD],
		]) -> void:
	var little := Real.instance("EBP02-033")
	var state := States.make_state({"p0": {"zone_cards": {2: little}}})
	var s := _session(state)
	var jr := Real.instance("EBP03-051")

	assert_bool(await _play(s, 0, from, 2, jr)).is_true()

	assert_array(state.players[0].zones[2]) \
		.override_failure_message("Godzilla Jr. from %s" % Source.keys()[from]) \
		.contains_exactly([jr, little])
	assert_bool(state.players[0].discard_pile.has(little)).is_false()
	_teardown(s)
