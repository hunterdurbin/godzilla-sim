class_name KaijuOpponentProfile
extends RefCounted

## Builds an opponent-tendency profile from stored live replays so the KAIJU
## evaluator can replace its static priors (e.g. opp_cp_growth) with measured
## behavior. LIVE-PATH ONLY: game_session wires it for KAIJU bots;
## bot_simulation_runner never does — headless sim seed-determinism depends
## on config.kaiju_opponent_profile staying empty there.
##
## compute_profile() is pure (fixture replay dicts in unit tests);
## build_for_opponent_async() adds the disk scan, spreading full JSON parses
## one per frame so match setup never hitches.

const MAX_GAMES := 10
const MIN_GAMES := 3
const MAX_FILE_BYTES := 4 * 1024 * 1024
# Replay JSON writes metadata before "snapshots" (ReplayData.to_dict order),
# so a small head read suffices to match names / reject sims without parsing.
const HEADER_PROBE_BYTES := 2048
const RECENCY_HALF_LIFE := 5.0 # weight = 0.5^(age_index / HALF_LIFE)
const DECK_MATCH_BOOST := 1.5
const IGNORED_NAMES: Array[String] = ["", "Bot", "Player 1", "Player 2"]


## Scan the current game version's recent/ + favorites/ replay dirs for games
## involving opponent_name, newest-first, and build the profile. Returns {}
## when the name is blocklisted, fewer than MIN_GAMES usable games exist, or
## the dirs are missing.
static func build_for_opponent_async(opponent_name: String, id_to_card: Callable,
		tree: SceneTree, opponent_deck: String = "") -> Dictionary:
	if opponent_name in IGNORED_NAMES:
		return {}
	var candidates := _list_candidates(opponent_name)
	var replays: Array = []
	for path in candidates:
		if replays.size() >= MAX_GAMES:
			break
		if tree != null:
			await tree.process_frame # one full parse per frame — no setup hitch
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			replays.append(parsed)
	return compute_profile(replays, opponent_name, id_to_card, opponent_deck)


## Pure core. `replays` is Array[Dictionary], newest-first. Games that don't
## involve opponent_name, are sims, or have fewer than 2 turns are skipped.
static func compute_profile(replays: Array, opponent_name: String,
		id_to_card: Callable, opponent_deck: String = "") -> Dictionary:
	if opponent_name in IGNORED_NAMES:
		return {}
	var sums: Dictionary = {} # key -> {"num": float, "weight": float}
	var files: Array[String] = []
	var games: int = 0
	var weight_total: float = 0.0
	for i in range(replays.size()):
		var replay: Dictionary = replays[i]
		if str(replay.get("mode", "")) == "sim":
			continue
		var names: Array = replay.get("player_names", [])
		var opp_pid: int = names.find(opponent_name)
		if opp_pid < 0:
			continue
		var stats := _game_stats(replay, opp_pid, id_to_card)
		if stats.is_empty():
			continue
		var weight: float = pow(0.5, games / RECENCY_HALF_LIFE)
		var decks: Array = replay.get("deck_names", [])
		if not opponent_deck.is_empty() and opp_pid < decks.size() \
				and str(decks[opp_pid]) == opponent_deck:
			weight *= DECK_MATCH_BOOST
		for key in stats:
			if not sums.has(key):
				sums[key] = {"num": 0.0, "weight": 0.0}
			sums[key]["num"] += stats[key] * weight
			sums[key]["weight"] += weight
		games += 1
		weight_total += weight
		files.append(str(replay.get("label", "")))
	if games < MIN_GAMES:
		return {}

	var profile: Dictionary = {
		"games": games,
		"weight_total": weight_total,
		"source": {"opponent": opponent_name, "files": files},
	}
	for key in sums:
		profile[key] = sums[key]["num"] / maxf(sums[key]["weight"], 0.001)
	return profile


## Per-game tendency stats for the opponent, from a ReplayMetrics analysis.
## Keys absent when their signal is unavailable (sparse pre-event-fix replays
## carry only turn boundaries in log_lines; snapshot-derived stats survive).
static func _game_stats(replay: Dictionary, opp_pid: int, id_to_card: Callable) -> Dictionary:
	var analysis := ReplayMetrics.analyze_game(replay, id_to_card)
	var per_turn: Array = analysis.get("per_turn", [])
	var their_turns: Array[Dictionary] = []
	for entry in per_turn:
		if int(entry.get("actor", -1)) == opp_pid:
			their_turns.append(entry)
	if their_turns.size() < 2:
		return {}

	var cp_gain_total: float = 0.0
	var cards_played: float = 0.0 # played_battle tokens (falls back to board delta)
	var board_delta_total: float = 0.0
	var invade_steps: float = 0.0
	var zone_gain: float = 0.0
	var counters: float = 0.0
	var hand_total: float = 0.0
	var early_invaded := false
	var prev_cp: float = -1.0
	var prev_board: float = -1.0
	var prev_zone: float = -1.0
	for entry in per_turn: # walk ALL turns so deltas span the opponent's gaps
		var them: Dictionary = entry["players"][opp_pid]
		if int(entry.get("actor", -1)) == opp_pid:
			var zone_step: float = 0.0
			if prev_cp >= 0.0:
				cp_gain_total += maxf(0.0, float(them["board_cp"]) - prev_cp)
			if prev_board >= 0.0:
				board_delta_total += maxf(0.0, float(them.get("board_cards", 0)) - prev_board)
			if prev_zone >= 0.0:
				zone_step = maxf(0.0, float(them.get("zone", 1)) - prev_zone)
			invade_steps += float(them.get("invade_steps", 0))
			zone_gain += zone_step
			counters += float(them.get("counters_landed", 0))
			hand_total += float(them.get("hand_count", 0))
			if int(entry.get("turn", 99)) < 5 \
					and (float(them.get("invade_steps", 0)) > 0.0 or zone_step > 0.0):
				early_invaded = true
		prev_cp = float(them["board_cp"])
		prev_board = float(them.get("board_cards", 0))
		prev_zone = float(them.get("zone", 1))

	var n: float = their_turns.size()
	var tokens_played: float = _count_played_battle(replay, opp_pid)
	cards_played = tokens_played if tokens_played > 0.0 else board_delta_total

	var stats: Dictionary = {
		"cp_growth_per_turn": cp_gain_total / n,
		"invade_tempo": (invade_steps if invade_steps > 0.0 else zone_gain) / n,
		"hand_hoard": hand_total / n,
		"early_invader": 1.0 if early_invaded else 0.0,
		"zone_at_turn8": _zone_at_turn(per_turn, opp_pid, 8),
	}
	if cards_played > 0.0:
		stats["cp_per_card"] = cp_gain_total / cards_played
	if _has_counter_tokens(replay):
		stats["counters_per_turn"] = counters / n
	return stats


static func _count_played_battle(replay: Dictionary, opp_pid: int) -> float:
	var count: float = 0.0
	for snap in replay.get("snapshots", []):
		for token in snap.get("log_lines", []):
			if token.get("type", "") == "played_battle" and int(token.get("player_id", -1)) == opp_pid:
				count += 1.0
	return count


static func _has_counter_tokens(replay: Dictionary) -> bool:
	for snap in replay.get("snapshots", []):
		for token in snap.get("log_lines", []):
			var t: String = token.get("type", "")
			if t == "counter_succeeded" or t == "counter_failed":
				return true
	return false


static func _zone_at_turn(per_turn: Array, opp_pid: int, turn: int) -> float:
	var zone: float = 1.0
	for entry in per_turn:
		zone = float(entry["players"][opp_pid].get("zone", 1))
		if int(entry.get("turn", 0)) >= turn:
			break
	return zone


## Candidate replay paths newest-first: cheap header probe (name appears +
## not a sim) before any full parse.
static func _list_candidates(opponent_name: String) -> Array[String]:
	var ver: String = ReplayData._get_game_version()
	var paths: Array[String] = []
	for dir_path in [ReplayData.get_version_recent_dir(ver), ReplayData.get_version_favorites_dir(ver)]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for fname in dir.get_files():
			if fname.ends_with(".json"):
				paths.append(dir_path.path_join(fname))
	paths.sort() # replay_<timestamp>.json — lexicographic == chronological
	paths.reverse() # newest first
	var matched: Array[String] = []
	for path in paths:
		if _header_matches(path, opponent_name):
			matched.append(path)
	return matched


static func _header_matches(path: String, opponent_name: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	if f.get_length() > MAX_FILE_BYTES:
		f.close()
		return false
	var head := f.get_buffer(mini(HEADER_PROBE_BYTES, f.get_length())).get_string_from_utf8()
	f.close()
	if head.find("\"mode\": \"sim\"") >= 0 or head.find("\"mode\":\"sim\"") >= 0:
		return false
	return head.find("\"%s\"" % opponent_name) >= 0
