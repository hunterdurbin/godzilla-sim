extends GdUnitTestSuite

## KaijuRollout — scratch-match cloning for the KAIJU planner. Verifies the
## snapshot round-trip, that applying actions mutates only the scratch state,
## clone independence, and fair-play determinization.

const GODZILLA_R1 := "ESD01-001" # rank 1 monster, threat 6000
const VANILLA_BATTLE := "ESD01-008" # battle, CP 2000, no effect script


func _build_state() -> GameState:
	var monster: Dictionary = CardData.get_card_by_id(GODZILLA_R1)
	var battle: Dictionary = CardData.get_card_by_id(VANILLA_BATTLE)
	assert_bool(monster.is_empty()).is_false()
	assert_bool(battle.is_empty()).is_false()

	var state := GameState.new()
	state.turn_number = 4
	state.current_player_id = 1
	state.current_phase = CardEnums.GamePhase.MAIN
	state.current_sub_phase = 1
	for pid in range(2):
		var p := state.players[pid]
		p.current_monster = monster.duplicate(true)
		p.monster_zone = 3 if pid == 0 else 5
		p.rage = pid + 1
		for i in range(3):
			p.hand.append(battle.duplicate(true))
			p.main_deck.append(battle.duplicate(true))
		# A monster card in hand so GAIN_RAGE is a legal action for p1.
		p.hand.append(monster.duplicate(true))
		p.push_zone_card(2, battle.duplicate(true))
	return state


func _rollout_from(state: GameState) -> KaijuRollout:
	return KaijuRollout.new(KaijuRollout.snapshot(state), 1, BotConfig.kaiju())


func test_snapshot_round_trip_preserves_state() -> void:
	var source := _build_state()
	var rollout := _rollout_from(source)

	assert_int(rollout.state().turn_number).is_equal(4)
	assert_int(rollout.state().current_player_id).is_equal(1)
	for pid in range(2):
		var restored := rollout.state().players[pid]
		assert_int(restored.monster_zone).is_equal(source.players[pid].monster_zone)
		assert_int(restored.rage).is_equal(source.players[pid].rage)
		assert_int(restored.hand.size()).is_equal(source.players[pid].hand.size())
		assert_int(restored.main_deck.size()).is_equal(source.players[pid].main_deck.size())
		assert_bool(restored.zone_has_battle_card(2)).is_true()
	assert_int(rollout.state_hash()).is_equal(StateCodec.compute_state_hash(source))
	rollout.release()


func test_apply_mutates_scratch_not_source() -> void:
	var source := _build_state()
	var source_rage: int = source.players[1].rage
	var source_hand: int = source.players[1].hand.size()
	var rollout := _rollout_from(source)

	var monster_indices: Array[int] = rollout.rules().get_monster_cards_for_rage(rollout.state().players[1])
	assert_bool(monster_indices.is_empty()).is_false()
	var alive: bool = await rollout.apply(CardEnums.ActionType.GAIN_RAGE, {"hand_index": monster_indices[0]})

	assert_bool(alive).is_true()
	assert_int(rollout.state().players[1].rage).is_equal(source_rage + 1)
	assert_int(rollout.state().players[1].hand.size()).is_equal(source_hand - 1)
	# The live state is untouched.
	assert_int(source.players[1].rage).is_equal(source_rage)
	assert_int(source.players[1].hand.size()).is_equal(source_hand)
	rollout.release()


func test_clone_is_independent() -> void:
	var rollout := _rollout_from(_build_state())
	var branch := rollout.clone()

	var monster_indices: Array[int] = branch.rules().get_monster_cards_for_rage(branch.state().players[1])
	await branch.apply(CardEnums.ActionType.GAIN_RAGE, {"hand_index": monster_indices[0]})

	assert_int(branch.state().players[1].rage).is_equal(3)
	assert_int(rollout.state().players[1].rage).is_equal(2)
	branch.release()
	rollout.release()


func test_determinize_full_visibility_is_untouched() -> void:
	var snap := KaijuRollout.snapshot(_build_state())
	var out := KaijuRollout.determinize(snap, 0, BotConfig.InfoVisibility.FULL)
	assert_that(out).is_equal(snap)


func test_determinize_preserves_counts_and_pool() -> void:
	seed(1234)
	var snap := KaijuRollout.snapshot(_build_state())
	var opp_before: Dictionary = snap["players"][0]
	var out := KaijuRollout.determinize(snap, 0, BotConfig.InfoVisibility.COUNTS)
	var opp_after: Dictionary = out["players"][0]

	assert_int(opp_after["hand"].size()).is_equal(opp_before["hand"].size())
	assert_int(opp_after["main_deck"].size()).is_equal(opp_before["main_deck"].size())
	var pool_before: Array = opp_before["hand"] + opp_before["main_deck"]
	var pool_after: Array = opp_after["hand"] + opp_after["main_deck"]
	pool_before.sort()
	pool_after.sort()
	assert_that(pool_after).is_equal(pool_before)
	# The planner's own hand is never touched; own deck keeps its multiset
	# (order is hidden from a fair player, so it gets reshuffled too).
	assert_that(out["players"][1]["hand"]).is_equal(snap["players"][1]["hand"])
	var own_deck_before: Array = snap["players"][1]["main_deck"].duplicate()
	var own_deck_after: Array = out["players"][1]["main_deck"].duplicate()
	own_deck_before.sort()
	own_deck_after.sort()
	assert_that(own_deck_after).is_equal(own_deck_before)


func test_release_is_idempotent() -> void:
	var rollout := _rollout_from(_build_state())
	rollout.release()
	rollout.release()
	assert_object(rollout.tm).is_null()
