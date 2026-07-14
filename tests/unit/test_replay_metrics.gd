extends GdUnitTestSuite

## ReplayMetrics — pure replay analysis on hand-built snapshot/token dicts
## (no CardData autoload: card lookups go through a stub Callable).

const CARDS := {
	"MON-R2_0_0": {"rank": 2, "threat_level": 12000, "counter_power": 0},
	"BTL-A_0_1": {"rank": 1, "counter_power": 2000},
	"BTL-B_1_2": {"rank": 1, "counter_power": 3000},
}


static func _lookup(instance_id: String) -> Dictionary:
	return CARDS.get(instance_id, {})


func _player(zone: int, rage: int, hand: int, zones: Array) -> Dictionary:
	return {
		"monster_zone": zone, "rage": rage, "hand_count": hand,
		"current_monster": "MON-R2_0_0", "zones": zones,
	}


func _empty_zones() -> Array:
	var z: Array = []
	for i in range(8):
		z.append([])
	return z


func _replay() -> Dictionary:
	var z0 := _empty_zones()
	z0[2] = ["BTL-A_0_1"]
	var z1 := _empty_zones()
	z1[0] = ["BTL-B_1_2"]
	return {
		"game_seed": 42, "mode": "sim", "bot_difficulty": "KAIJU_vs_HARD",
		"winner_id": 0, "win_reason": "test", "total_turns": 2, "label": "t",
		"snapshots": [
			{
				"turn_number": 1, "current_player_id": 0, "phase": 1,
				"is_boundary": true,
				"players": [_player(1, 0, 5, _empty_zones()), _player(1, 0, 5, _empty_zones())],
				"log_lines": [
					{"type": "turn_start", "turn": 1, "player_id": 0},
					{"type": "gained_rage", "player_id": 0, "rage": 1, "card_id": "x"},
				],
			},
			{
				"turn_number": 1, "current_player_id": 0, "phase": 2,
				"is_boundary": false,
				"players": [_player(3, 1, 4, z0), _player(1, 0, 5, _empty_zones())],
				"log_lines": [
					{"type": "invaded", "player_id": 0, "card_id": "y", "is_step2": true},
					{"type": "counter_succeeded", "player_id": 0, "total_cp": 8000, "threat": 6000, "threat_rage": 0, "threat_effects": 0},
				],
			},
			{
				"turn_number": 2, "current_player_id": 1, "phase": 1,
				"is_boundary": true,
				"players": [_player(3, 1, 4, z0), _player(2, 0, 6, z1)],
				"log_lines": [
					{"type": "effect_destroyed_card", "source_player_id": 1, "target_player_id": 0, "destroyed_id": "BTL-A_0_1", "source_id": "s", "zone_index": 2},
				],
			},
		],
	}


func test_analyze_game_per_turn_metrics() -> void:
	var game := ReplayMetrics.analyze_game(_replay(), _lookup)
	assert_int(game["winner_id"]).is_equal(0)
	var turns: Array = game["per_turn"]
	assert_int(turns.size()).is_equal(2)

	var t1_p0: Dictionary = turns[0]["players"][0]
	assert_int(t1_p0["zone_delta"]).is_equal(2) # zone 1 -> 3 within turn 1
	assert_int(t1_p0["rage_gained"]).is_equal(1)
	assert_int(t1_p0["invade_steps"]).is_equal(2)
	assert_int(t1_p0["counters_landed"]).is_equal(1)
	assert_int(t1_p0["board_cp"]).is_equal(2000)
	assert_int(t1_p0["threat"]).is_equal(12000 + 5000) # base + 1 rage
	var counter: Dictionary = t1_p0["counter_events"][0]
	assert_int(counter["margin"]).is_equal(2000)
	assert_bool(counter["success"]).is_true()

	var t2_p1: Dictionary = turns[1]["players"][1]
	assert_int(t2_p1["destroys_inflicted"]).is_equal(1)
	var t2_p0: Dictionary = turns[1]["players"][0]
	assert_int(t2_p0["counters_suffered"]).is_equal(0)


func test_phase_bucketing_uses_latched_high_water_mark() -> void:
	var game := ReplayMetrics.analyze_game(_replay(), _lookup)
	# Max zone seen is 3 and turns are 1-2 -> both turns are "early".
	for entry in game["per_turn"]:
		assert_str(entry["phase"]).is_equal("early")
	assert_bool(game["phases"].has("early")).is_true()
	assert_bool(game["phases"].has("late")).is_false()


func test_aggregate_reports_win_rate_and_signals() -> void:
	var game := ReplayMetrics.analyze_game(_replay(), _lookup)
	var report := ReplayMetrics.aggregate([game, game])
	assert_float(report["win_rate"]["p0"]).is_equal(1.0)
	assert_float(report["win_rate"]["p1"]).is_equal(0.0)
	assert_int(report["schema_version"]).is_equal(1)
	assert_bool(report["signals"].is_empty()).is_false()
	var top: Dictionary = report["signals"][0]
	assert_bool(top.has("suggested_knobs")).is_true()
	# Markdown renders without error and mentions the win rate table.
	var md := ReplayMetrics.to_markdown(report, [game, game])
	assert_bool(md.contains("Winner vs loser by phase")).is_true()
