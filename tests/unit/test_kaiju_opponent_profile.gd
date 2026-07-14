extends GdUnitTestSuite

## KaijuOpponentProfile — opponent-tendency extraction from replay dicts
## (pure compute_profile; the disk scan is live-only). Fixtures are minimal
## replay dicts; card lookup is a fixture Callable (no CardData).

const OPP := "Alice" # opponent under test, always player 1 in fixtures


func _card_lookup(id: String) -> Dictionary:
	# Fixture card db: battle cards "B" 2000 CP; monster "M" rank 1.
	if id.begins_with("B"):
		return {"id": id, "counter_power": 2000, "rank": 1}
	if id.begins_with("M"):
		return {"id": id, "rank": 1, "threat_level": 3000}
	return {}


func _pstate(zone_count: int, hand: int = 5, monster_zone: int = 1) -> Dictionary:
	var zones: Array = []
	for i in range(8):
		zones.append(["B%d" % i] if i < zone_count else [])
	return {
		"monster_zone": monster_zone, "rage": 0, "hand_count": hand,
		"zones": zones, "current_monster": "M1",
	}


func _snap(turn: int, actor: int, p0: Dictionary, p1: Dictionary, tokens: Array = []) -> Dictionary:
	return {"turn_number": turn, "current_player_id": actor,
			"players": [p0, p1], "log_lines": tokens}


## 4-turn game: Alice (pid 1) plays 2 battle cards on her first turn
## (board 0 → 2, +4000 CP), invades + counters on her second.
func _fixture_game(with_tokens: bool = true, label: String = "g") -> Dictionary:
	var late: Array = [{"type": "invaded", "player_id": 1, "is_step2": false},
			{"type": "counter_succeeded", "player_id": 1, "total_cp": 4000, "threat": 3000}] if with_tokens else []
	return {
		"label": label, "mode": "solo_bot",
		"player_names": ["Soda", OPP], "deck_names": ["d1", "d2"],
		"winner_id": 1, "win_reason": "x", "total_turns": 4,
		"snapshots": [
			_snap(1, 0, _pstate(0), _pstate(0)),
			_snap(2, 1, _pstate(0), _pstate(2)), # Alice deploys 2 cards
			_snap(3, 0, _pstate(1), _pstate(2)),
			_snap(4, 1, _pstate(1), _pstate(2, 5, 2), late), # Alice invades to z2
		],
	}


func _games(n: int, with_tokens: bool = true) -> Array:
	var games: Array = []
	for i in range(n):
		var g := _fixture_game(with_tokens, "g%d" % i)
		# attach the deploy tokens to turn 2 (kept out of _fixture_game for reuse)
		if with_tokens:
			g["snapshots"][1]["log_lines"] = [
				{"type": "played_battle", "player_id": 1},
				{"type": "played_battle", "player_id": 1},
			]
		games.append(g)
	return games


func test_profile_matches_hand_computed_values() -> void:
	var profile := KaijuOpponentProfile.compute_profile(_games(3), OPP, _card_lookup)

	assert_int(profile["games"]).is_equal(3)
	# 2 cards for +4000 CP on her first turn → 2000 CP/card.
	assert_float(profile["cp_per_card"]).is_equal_approx(2000.0, 0.01)
	# +4000 over 2 of her turns.
	assert_float(profile["cp_growth_per_turn"]).is_equal_approx(2000.0, 0.01)
	# 1 invade step over 2 of her turns.
	assert_float(profile["invade_tempo"]).is_equal_approx(0.5, 0.01)
	# 1 counter over 2 of her turns.
	assert_float(profile["counters_per_turn"]).is_equal_approx(0.5, 0.01)
	assert_float(profile["hand_hoard"]).is_equal_approx(5.0, 0.01)
	assert_float(profile["early_invader"]).is_equal(1.0)


func test_sparse_logs_fall_back_to_snapshots() -> void:
	# Pre-event-fix replays: no gameplay tokens at all.
	var profile := KaijuOpponentProfile.compute_profile(_games(3, false), OPP, _card_lookup)

	assert_int(profile["games"]).is_equal(3)
	# board_cards delta fallback: 2 cards, +4000 CP → still 2000.
	assert_float(profile["cp_per_card"]).is_equal_approx(2000.0, 0.01)
	# zone_delta fallback: monster 1 → 2 on her second turn.
	assert_float(profile["invade_tempo"]).is_equal_approx(0.5, 0.01)
	# No counter tokens anywhere → key absent (consumer treats as neutral).
	assert_bool(profile.has("counters_per_turn")).is_false()


func test_below_min_games_returns_empty() -> void:
	assert_that(KaijuOpponentProfile.compute_profile(_games(2), OPP, _card_lookup)).is_equal({})


func test_blocklisted_names_return_empty() -> void:
	assert_that(KaijuOpponentProfile.compute_profile(_games(3), "Bot", _card_lookup)).is_equal({})
	assert_that(KaijuOpponentProfile.compute_profile(_games(3), "", _card_lookup)).is_equal({})


func test_name_mismatch_and_sim_games_excluded() -> void:
	var games := _games(3)
	games[0]["player_names"] = ["Soda", "SomeoneElse"]
	games[1]["mode"] = "sim"
	# Only 1 usable game remains → below MIN_GAMES.
	assert_that(KaijuOpponentProfile.compute_profile(games, OPP, _card_lookup)).is_equal({})


func test_recency_weighting_favors_newer_games() -> void:
	var games := _games(3)
	# Newest game: 2 cards but +8000 CP (4000/card): give her 4 board cards
	# worth 2000 each on turn 2 while still playing 2 "played_battle" tokens.
	games[0]["snapshots"][1]["players"][1] = _pstate(4)
	games[0]["snapshots"][2]["players"][1] = _pstate(4)
	games[0]["snapshots"][3]["players"][1] = _pstate(4, 5, 2)

	var profile := KaijuOpponentProfile.compute_profile(games, OPP, _card_lookup)
	# Newest says 4000/card, older two say 2000/card: the recency-weighted
	# mean must land above the flat average of ~2667.
	assert_float(profile["cp_per_card"]).is_greater(2667.0)
	assert_float(profile["cp_per_card"]).is_less(4000.0)


func test_deck_match_boost_applies() -> void:
	var games := _games(3)
	games[0]["snapshots"][1]["players"][1] = _pstate(4)
	games[0]["snapshots"][2]["players"][1] = _pstate(4)
	games[0]["snapshots"][3]["players"][1] = _pstate(4, 5, 2)
	var neutral := KaijuOpponentProfile.compute_profile(games, OPP, _card_lookup)
	games[0]["deck_names"] = ["d1", "special"]
	var boosted := KaijuOpponentProfile.compute_profile(games, OPP, _card_lookup, "special")
	# Boosting the (newest, 4000/card) game pulls the mean further up.
	assert_float(boosted["cp_per_card"]).is_greater(neutral["cp_per_card"])
