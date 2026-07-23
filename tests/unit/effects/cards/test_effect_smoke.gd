extends GdUnitTestSuite

## Tier A smoke + consistency suite covering EVERY per-card effect script.
##
## Consistency checks: every script loads as a CardEffect, trigger_map.gd is
## current, TRIGGER_FILTERS only reference mapped methods, and the generator's
## METHODS list covers all CardEffect virtuals.
##
## Crash sweep: each card is placed on a populated board and every trigger its
## script declares is fired through the real EffectHandler dispatch (registry →
## trigger_map → TRIGGER_FILTERS → standby), with PlayerInput defaults answering
## prompts. A scripted-error crash aborts the awaited coroutine, so the test
## hangs and fails on timeout — the per-card print identifies the culprit.

const Cards := preload("res://tests/fixtures/cards.gd")
const States := preload("res://tests/fixtures/states.gd")
const Real := preload("res://tests/fixtures/real_cards.gd")
const TriggerMap := preload("res://scripts/effects/trigger_map.gd")

const SETS := ["ebp01", "ebp02", "ebp03", "ebp04", "esd01", "esd02", "epr", "esc01", "efc01"]

const REGENERATE_HINT := "Run: bash scripts/effects/generate_trigger_map.sh (never while a headless game/harness is running)"

## CardEffect methods intentionally absent from the generator's METHODS list:
## bot heuristics and helpers that are queried directly via get_effect(),
## never gated through has_trigger().
const METHODS_EXEMPT_PREFIXES := ["get_bot_", "bot_can_fulfill_"]
const METHODS_EXEMPT_NAMES := [
	"is_discard_play_optional", "find_zone_of_card",
	# Turn-scoped state round-trip hooks — called directly by GameSerializer /
	# MatchFactory, never dispatched through the trigger map.
	"serialize_state", "restore_state",
	# Collection-time gate — direct-called by the dispatcher on effects that
	# already passed has_trigger(on_phase_start), never has_trigger()-gated.
	"phase_start_applies",
]


# --- Consistency checks ---


func test_all_effect_scripts_load_and_instantiate() -> void:
	var ids := Real.ids_with_effects()
	assert_int(ids.size()).is_greater(300)
	for id in ids:
		var path: String = CardData.CARD_TEMPLATES[id].get("effect_script", "")
		assert_bool(ResourceLoader.exists(path)) \
			.override_failure_message("%s: effect_script missing on disk: %s" % [id, path]).is_true()
		var script: GDScript = load(path)
		assert_object(script).override_failure_message("%s: failed to load %s" % [id, path]).is_not_null()
		var effect: Object = script.new()
		assert_bool(effect is CardEffect) \
			.override_failure_message("%s: %s does not extend CardEffect" % [id, path]).is_true()


func test_every_effect_script_on_disk_is_referenced_by_a_template() -> void:
	var referenced := {}
	for id in CardData.CARD_TEMPLATES:
		var path: String = CardData.CARD_TEMPLATES[id].get("effect_script", "")
		if not path.is_empty():
			referenced[path] = true
	for path in _effect_script_paths():
		assert_bool(referenced.has(path)) \
			.override_failure_message("Effect script not referenced by any CARD_TEMPLATES entry: %s" % path) \
			.is_true()


func test_trigger_map_is_current() -> void:
	## trigger_map.gd must match what each script actually overrides — a stale
	## map silently disables triggers in-game (has_trigger gates dispatch).
	var tracked := _generator_methods()
	for path in _effect_script_paths():
		# Mirror the generator's `grep -q "func <method>("` so this check is
		# exactly "was generate_trigger_map.sh re-run". (get_script_method_list
		# can't be used: it includes inherited CardEffect methods.)
		var src: String = (load(path) as GDScript).source_code
		var actual: Array[String] = []
		for method_name in tracked:
			if src.contains("func %s(" % method_name):
				actual.append(method_name)
		var mapped: Array = TriggerMap.TRIGGERS.get(path, []).duplicate()
		actual.sort()
		mapped.sort()
		assert_array(mapped) \
			.override_failure_message("trigger_map.gd is stale for %s\n  script overrides: %s\n  map lists:        %s\n  %s" % [path, actual, mapped, REGENERATE_HINT]) \
			.contains_exactly_in_any_order(actual)


func test_trigger_filters_reference_mapped_methods() -> void:
	## A TRIGGER_FILTERS key for a method the script doesn't override (per the
	## trigger map) is dead config — the dispatcher never reads it.
	for path in _effect_script_paths():
		var script: GDScript = load(path)
		var filters: Dictionary = script.get_script_constant_map().get("TRIGGER_FILTERS", {})
		var mapped: Array = TriggerMap.TRIGGERS.get(path, [])
		for method_name in filters:
			assert_bool(method_name in mapped) \
				.override_failure_message("%s: TRIGGER_FILTERS[\"%s\"] but the trigger map has no such override. %s" % [path, method_name, REGENERATE_HINT]) \
				.is_true()


func test_generator_methods_list_covers_card_effect_virtuals() -> void:
	## New CardEffect virtual? It must also be added to METHODS in
	## generate_trigger_map.sh or has_trigger() never sees overrides of it.
	var tracked := _generator_methods()
	var card_effect_script: GDScript = load("res://scripts/effects/card_effect.gd")
	for m in card_effect_script.get_script_method_list():
		var method_name: String = m["name"]
		if method_name.begins_with("_") or m["flags"] & METHOD_FLAG_STATIC:
			continue
		if method_name in METHODS_EXEMPT_NAMES:
			continue
		var exempt := false
		for prefix in METHODS_EXEMPT_PREFIXES:
			if method_name.begins_with(prefix):
				exempt = true
				break
		if exempt:
			continue
		assert_bool(method_name in tracked) \
			.override_failure_message("CardEffect.%s is missing from METHODS in scripts/effects/generate_trigger_map.sh — add it and regenerate, or exempt it in this test if it is never has_trigger()-gated." % method_name) \
			.is_true()


# --- Crash sweep ---


func test_crash_sweep_ebp01(_timeout := 300000) -> void:
	await _sweep_set("ebp01")


func test_crash_sweep_ebp02(_timeout := 300000) -> void:
	await _sweep_set("ebp02")


func test_crash_sweep_ebp03(_timeout := 300000) -> void:
	await _sweep_set("ebp03")


func test_crash_sweep_ebp04(_timeout := 300000) -> void:
	await _sweep_set("ebp04")


func test_crash_sweep_small_sets(_timeout := 300000) -> void:
	for set_prefix in ["esd01", "esd02", "epr", "esc01", "efc01"]:
		await _sweep_set(set_prefix)


func _sweep_set(set_prefix: String) -> void:
	var ids := Real.ids_for_set(set_prefix)
	assert_int(ids.size()).override_failure_message("No cards found for set %s" % set_prefix).is_greater(0)
	for id in ids:
		print("[smoke] %s" % id)
		await _sweep_card(id)


func _sweep_card(id: String) -> void:
	var card := Real.instance(id)
	var script_path: String = card.get("effect_script", "")
	var methods: Array = TriggerMap.TRIGGERS.get(script_path, [])

	var state := States.make_state({"p0": _generic_opts(0), "p1": _generic_opts(1)})
	var p0 := state.players[0]
	var card_zone := -1
	match int(card.get("card_type", -1)):
		CardEnums.CardType.MONSTER:
			p0.current_monster = card
			p0.monster_zone = 4
		CardEnums.CardType.BATTLE:
			card_zone = 2
			p0.push_zone_card(card_zone, card)
		CardEnums.CardType.STRATEGY:
			p0.strategy_zones[1] = card
	var session := States.make_session(state)
	var handler: EffectHandler = session["effect_handler"]

	await _query_sweep(handler, state, card)
	await _dispatch_sweep(handler, state, card, methods)
	await _destruction_sweep(handler, state, card, card_zone)
	_assert_state_sane(state, id)


## Exercise every passive getter override through the real aggregation layer
## (EffectQueries / destruction protection), for both players.
func _query_sweep(handler: EffectHandler, state: GameState, card: Dictionary) -> void:
	for pid in range(2):
		handler.is_rage_reduction_prevented(pid)
		handler.can_monster_be_played_from_hand(pid, card)
		handler.get_counter_power_modifier(pid)
		handler.get_monster_cp_modifier(pid)
		handler.get_strategy_cp_modifiers(pid)
		handler.get_zone_cp_modifiers(pid)
		handler.get_threat_level_modifier(pid)
		handler.get_effective_threat_level(pid)
		handler.get_play_rank_modifier(pid, card)
		handler.should_stack_on_play(pid, card, 2)
		handler.get_zone_play_rank_modifier(pid, card, 2)
		handler.is_invasion_blocked(pid)
		handler.get_engagement_restriction(pid)
		handler.get_engagement_restricted_cp(pid)
		handler.get_cards_that_can_engage(pid)
		handler.get_opponent_blocked_zones(pid)
		handler.get_extra_end_phase_advance(pid)
		handler.get_invasion_advance_bonus(pid, 1)
		handler.can_play_as_monster(pid, card)
		handler.is_monster_advance_blocked(pid)
		handler.is_own_invasion_blocked(pid)
		handler.can_replace_invasion_cost(pid)
		handler.get_counter_immunity_threshold(pid)
		handler.is_counter_prevented(pid, 10000)
		handler.are_opponent_strategy_plays_blocked(pid)
		handler.get_opponent_field_rank_modifier(pid)
		handler.prevents_self_start_phase_discard(pid, card)
		handler.can_card_be_played(pid, card)
		handler.get_card_required_play_zones(pid, card)
		handler.get_effective_field_rank(card, pid)
		handler.get_zones_in_rank_range(pid, 1, 8)
		handler.get_effective_zone_cp(pid, 2)
		handler.get_zones_in_cp_range(pid, 0, 99999)
		handler.get_zone_rank_modifiers(pid)
		handler.is_opponent_end_phase_draw_blocked(pid)
		handler.is_opponent_monster_move_blocked(pid)
		handler.is_invade1_cost_blocked(pid)
		handler.get_strategy_hand_rank_modifier(pid, card)
		handler.get_strategy_discard_interceptor(pid)
		handler.can_destroy_card(state.players[pid], card)
	handler.is_base_strategy(card)
	await handler.apply_rage_reset(0)


## Fire each trigger the script's map entry declares, through the public
## dispatch path closest to the real game flow.
func _dispatch_sweep(handler: EffectHandler, state: GameState, card: Dictionary, methods: Array) -> void:
	var p0 := state.players[0]
	var p1 := state.players[1]

	if "on_enter" in methods:
		await handler.trigger_enter(0, card)

	if "on_when_invading" in methods and not p0.current_monster.is_empty():
		await handler.trigger_when_invading(0, p0.monster_zone, p0.monster_zone + 1)

	if "on_monster_advance" in methods:
		await handler.trigger_monster_advance(0, p0.monster_zone, p0.monster_zone + 1)

	if "on_rage_changed" in methods or "on_opponent_rage_changed" in methods or "on_rage_reset" in methods:
		await handler.gain_rage(0, 1)
		await handler.reduce_rage(0, 1)
		await handler.gain_rage(1, 1)
		await handler.reduce_rage(1, 1)

	if "on_phase_start" in methods or "on_phase_end" in methods:
		for phase in [CardEnums.GamePhase.START, CardEnums.GamePhase.MAIN, CardEnums.GamePhase.COUNTER, CardEnums.GamePhase.END]:
			state.current_phase = phase
			if "on_phase_start" in methods:
				await handler.trigger_phase_start(phase)
			if "on_phase_end" in methods:
				await handler.trigger_phase_end(phase)
		state.current_phase = CardEnums.GamePhase.MAIN

	if "on_monster_played" in methods or "can_play_from_discard_on_monster_played" in methods:
		await handler.trigger_monster_played(0, {}, p0.current_monster)

	if "on_battle_card_played" in methods:
		var played := Cards.battle(3, 4000, "SMOKE-PLAYED")
		p0.push_zone_card(5, played)
		await handler.trigger_battle_card_played(0, played, 5, false)
		await handler.trigger_battle_card_played(0, played, 5, true)
		var opp_played := Cards.battle(3, 4000, "SMOKE-OPP-PLAYED")
		p1.push_zone_card(5, opp_played)
		await handler.trigger_battle_card_played(1, opp_played, 5, false)

	if "on_hand_card_discarded" in methods:
		for discarded in [Cards.battle(2, 3000, "SMOKE-DISC-B"), Cards.strategy(2, "SMOKE-DISC-S"), Cards.monster(2, 9000, [], "SMOKE-DISC-M")]:
			p0.discard_pile.append(discarded)
			await handler.trigger_hand_card_discarded(0, discarded)

	if "on_discard_from_hand" in methods:
		var self_discarded := Real.instance(card.get("id", "").get_slice("_T_", 0), 1)
		p0.discard_pile.append(self_discarded)
		await handler.trigger_discard_from_hand(0, self_discarded)

	if "on_burst_discard" in methods:
		var burst_copy := Real.instance(card.get("id", "").get_slice("_T_", 0), 2)
		p0.discard_pile.append(burst_copy)
		await handler.trigger_burst_discard(0, burst_copy)

	if "on_counter_success" in methods or "on_self_countered" in methods:
		await handler.trigger_counter_success(0, 1)
		await handler.trigger_counter_success(1, 0)

	if "on_strategy_discarded" in methods:
		var discarded_strategy := Cards.strategy(2, "SMOKE-STRAT-DISC")
		p0.discard_pile.append(discarded_strategy)
		await handler.trigger_strategy_discarded(0, discarded_strategy)

	if "on_invasion_observed" in methods:
		await handler.trigger_invasion_observed(0, 4, 5)
		await handler.trigger_invasion_observed(1, 4, 5)

	if "on_discarded_for_invasion" in methods:
		var invasion_copy := Real.instance(card.get("id", "").get_slice("_T_", 0), 3)
		p0.discard_pile.append(invasion_copy)
		var entries: Array = handler.collect_discarded_for_invasion_entries(0, invasion_copy)
		await handler.resolve_deferred_entries(entries)

	if "on_ally_zone_card_destroyed" in methods or "on_opponent_zone_card_destroyed" in methods:
		var bystander := Cards.battle(2, 3000, "SMOKE-DESTROYED")
		await handler.trigger_ally_zone_card_destroyed(0, bystander, 4)
		await handler.trigger_opponent_zone_card_destroyed(1, bystander, 4)

	if "on_card_returned_from_discard" in methods:
		var returned := Cards.battle(2, 3000, "SMOKE-RETURNED")
		await handler.trigger_card_returned_from_discard(0, returned)
		await handler.trigger_card_returned_from_discard(1, returned)

	if "apply_play_cost" in methods:
		var zone_for_cost: int = -1 if int(card.get("card_type", -1)) == CardEnums.CardType.MONSTER else 2
		await handler.apply_play_cost(0, card, zone_for_cost)

	if "on_leave_play" in methods:
		# Direct leave-play (returns to hand/deck paths); destruction path runs below.
		await handler.trigger_leave_play(0, card, 2)

	if "on_zone_changed" in methods and int(card.get("card_type", -1)) == CardEnums.CardType.BATTLE:
		var zidx := _find_zone_of(p0, card)
		if zidx >= 0:
			await handler.move_zone_stack(p0, zidx, 1 if zidx != 1 else 0)


## Destroy a generic battle card (exercises watcher triggers and strategy
## protections), the real card's own zone if it is a battle card (exercises
## can_be_destroyed / on_would_be_destroyed / on_destroy / on_revenge /
## on_leave_play), and a strategy discard (exercises interceptors).
func _destruction_sweep(handler: EffectHandler, state: GameState, card: Dictionary, _card_zone: int) -> void:
	var p0 := state.players[0]
	if p0.zone_has_battle_card(4):
		await handler.destroy_zones(p0, [4])
	if int(card.get("card_type", -1)) == CardEnums.CardType.BATTLE:
		var zidx := _find_zone_of(p0, card)
		if zidx >= 0:
			await handler.destroy_zones(p0, [zidx])
	if not p0.strategy_zones[0].is_empty():
		await handler.discard_strategy_from_zone(0, 0)


func _assert_state_sane(state: GameState, id: String) -> void:
	for pid in range(2):
		var player := state.players[pid]
		assert_bool(player.monster_zone >= 1 and player.monster_zone <= 9) \
			.override_failure_message("%s: player %d monster_zone out of range: %d" % [id, pid, player.monster_zone]) \
			.is_true()
		for i in range(8):
			assert_object(player.get_zone_stack(i)) \
				.override_failure_message("%s: player %d zone %d stack missing" % [id, pid, i]).is_not_null()


func _generic_opts(pid: int) -> Dictionary:
	return {
		"hand": [
			Cards.battle(2, 3000, "P%d-HAND-B1" % pid),
			Cards.battle(4, 5000, "P%d-HAND-B2" % pid),
			Cards.strategy(3, "P%d-HAND-S1" % pid),
		],
		"main_deck": [
			Cards.battle(1, 2000, "P%d-DECK-B1" % pid),
			Cards.battle(3, 4000, "P%d-DECK-B2" % pid),
			Cards.strategy(2, "P%d-DECK-S1" % pid),
			Cards.battle(5, 6000, "P%d-DECK-B3" % pid),
			Cards.monster(2, 12000, [CardEnums.CardTrait.GODZILLA], "P%d-DECK-M1" % pid),
			Cards.battle(2, 3000, "P%d-DECK-B4" % pid),
		],
		"monster_deck": Cards.monster_line([CardEnums.CardTrait.GODZILLA], "P%d-MON" % pid),
		"rage": 2,
		"monster_zone": 4,
		"zone_cards": {4: Cards.battle(2, 3000, "P%d-Z5" % pid)},
		"strategy_zones": [Cards.strategy(2, "P%d-STRAT" % pid)],
	}


func _find_zone_of(player: PlayerState, card: Dictionary) -> int:
	for i in range(8):
		if player.get_zone_top_card(i).get("id", "") == card.get("id", ""):
			return i
	return -1


# --- Helpers for consistency checks ---


func _effect_script_paths() -> Array[String]:
	var paths: Array[String] = []
	for set_prefix in SETS:
		var dir_path := "res://scripts/effects/%s" % set_prefix
		for file in DirAccess.get_files_at(dir_path):
			if file.ends_with(".gd"):
				paths.append("%s/%s" % [dir_path, file])
	paths.sort()
	assert_int(paths.size()).override_failure_message("No effect scripts found on disk").is_greater(300)
	return paths


## The METHODS list parsed from generate_trigger_map.sh — single source of
## truth for which CardEffect virtuals the trigger map tracks.
func _generator_methods() -> Array[String]:
	var text := FileAccess.get_file_as_string("res://scripts/effects/generate_trigger_map.sh")
	assert_str(text).is_not_empty()
	var start := text.find("METHODS=(")
	assert_int(start).override_failure_message("METHODS=( not found in generate_trigger_map.sh").is_greater(-1)
	var end := text.find(")", start)
	var block := text.substr(start + "METHODS=(".length(), end - start - "METHODS=(".length())
	var methods: Array[String] = []
	for token in block.split(" ", false):
		for sub in token.split("\n", false):
			var trimmed := sub.strip_edges().trim_prefix("\t")
			if not trimmed.is_empty() and not trimmed.begins_with("#") and not methods.has(trimmed):
				methods.append(trimmed)
	assert_int(methods.size()).is_greater(40)
	return methods
