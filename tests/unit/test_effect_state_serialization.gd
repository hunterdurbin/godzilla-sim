extends GdUnitTestSuite

## CardEffect.serialize_state / restore_state — turn-scoped effect member
## state must round-trip through GameSerializer.serialize_player_state →
## MatchFactory.setup_from_save (the save-game AND KaijuRollout clone path).
## The two stateful effects: EBP03-032 (_bonus_cp, rest-of-turn counter CP)
## and EBP04-014 (_counter_prevention_threshold, until end of turn).

const MECHAGODZILLA_1974 := "EBP03-032" # battle R4, turn-scoped _bonus_cp
const GODZILLA_2002 := "EBP04-014" # monster R2, turn-scoped prevention threshold
const GODZILLA_R1 := "ESD01-001" # vanilla-ish monster for the opponent


func _build_state() -> GameState:
	var state := GameState.new()
	state.turn_number = 6
	state.current_player_id = 0 # P0's turn: EBP03-032's modifier only counts on the owner's turn
	state.current_phase = CardEnums.GamePhase.MAIN
	var p0 := state.players[0]
	p0.current_monster = CardData.get_card_by_id(GODZILLA_2002)
	p0.monster_zone = 4
	p0.push_zone_card(2, CardData.get_card_by_id(MECHAGODZILLA_1974))
	var p1 := state.players[1]
	p1.current_monster = CardData.get_card_by_id(GODZILLA_R1)
	p1.monster_zone = 1
	assert_bool(p0.current_monster.is_empty()).is_false()
	assert_bool(p0.get_zone_top_card(2).is_empty()).is_false()
	return state


func _handler_for(state: GameState) -> EffectHandler:
	var handler := EffectHandler.new()
	handler.setup(state, ScriptedPlayerInput.new())
	return handler


## Seed the two effects' turn-scoped state via restore_state (same setter the
## load path uses) and return the handler.
func _seeded_handler(state: GameState) -> EffectHandler:
	var handler := _handler_for(state)
	handler.get_effect(state.players[0].get_zone_top_card(2)).restore_state({"bonus_cp": 3000})
	handler.get_effect(state.players[0].current_monster).restore_state({"counter_prevention_threshold": 30000})
	return handler


func test_serialize_without_handler_emits_no_effect_state() -> void:
	var state := _build_state()
	_seeded_handler(state)
	var data := GameSerializer.serialize_player_state(state.players[0])
	assert_bool(data.has("effect_state")).is_false()


func test_serialize_skips_stateless_effects() -> void:
	var state := _build_state()
	var handler := _handler_for(state) # nothing seeded — both effects at defaults
	var data := GameSerializer.serialize_player_state(state.players[0], handler)
	assert_bool(data.has("effect_state")).is_false()


func test_serialize_emits_state_keyed_by_instance_id() -> void:
	var state := _build_state()
	var handler := _seeded_handler(state)
	var data := GameSerializer.serialize_player_state(state.players[0], handler)

	var effect_state: Dictionary = data.get("effect_state", {})
	var battle_id: String = state.players[0].get_zone_top_card(2).get("id", "")
	var monster_id: String = state.players[0].current_monster.get("id", "")
	assert_that(effect_state.get(battle_id)).is_equal({"bonus_cp": 3000})
	assert_that(effect_state.get(monster_id)).is_equal({"counter_prevention_threshold": 30000})


func test_rollout_round_trip_restores_effect_queries() -> void:
	var state := _build_state()
	var handler := _seeded_handler(state)

	var rollout := KaijuRollout.new(KaijuRollout.snapshot(state, handler), 0, BotConfig.kaiju())
	# EBP03-032's rest-of-turn bonus survives into the scratch match's queries.
	assert_int(rollout.queries().get_counter_power_modifier(0)).is_equal(3000)
	# EBP04-014's prevention threshold survives (prevented at <= 30k, not above).
	assert_bool(rollout.queries().is_counter_prevented(0, 25000)).is_true()
	assert_bool(rollout.queries().is_counter_prevented(0, 40000)).is_false()
	rollout.release()


func test_rollout_without_effect_state_stays_at_defaults() -> void:
	var state := _build_state()
	_seeded_handler(state)

	# Snapshot WITHOUT the handler: state must not leak through card dicts.
	var rollout := KaijuRollout.new(KaijuRollout.snapshot(state), 0, BotConfig.kaiju())
	assert_int(rollout.queries().get_counter_power_modifier(0)).is_equal(0)
	assert_bool(rollout.queries().is_counter_prevented(0, 25000)).is_false()
	rollout.release()


func test_restore_state_coerces_json_floats() -> void:
	# Save files round-trip through JSON, which turns ints into floats.
	var state := _build_state()
	var handler := _handler_for(state)
	var battle_effect := handler.get_effect(state.players[0].get_zone_top_card(2))
	battle_effect.restore_state({"bonus_cp": 3000.0})
	assert_that(battle_effect.serialize_state()).is_equal({"bonus_cp": 3000})
	var monster_effect := handler.get_effect(state.players[0].current_monster)
	monster_effect.restore_state({"counter_prevention_threshold": 30000.0})
	assert_that(monster_effect.serialize_state()).is_equal({"counter_prevention_threshold": 30000})
