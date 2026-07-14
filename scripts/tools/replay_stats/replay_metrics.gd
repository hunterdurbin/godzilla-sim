class_name ReplayMetrics
extends RefCounted

## Pure replay-analysis metrics: turns a replay dictionary (ReplayData JSON)
## into per-turn tempo / threat / CP / card-advantage records, phase-bucketed
## summaries, and a cross-game aggregate designed for an AI tuning agent to
## map findings onto BotConfig knobs. No autoload dependency — card lookups
## go through an injected Callable (production: GameSerializer.id_to_card).
##
## Game phases use the same latched high-water mark as KaijuEvaluator:
## once either monster has reached a zone threshold (or a turn threshold
## passes), the game stays in that phase even when monsters retreat.

const SCHEMA_VERSION: int = 1

## Metric key → BotConfig knob paths an agent should consider adjusting when
## the winner-minus-loser delta on that metric is large.
const KNOB_MAP: Dictionary = {
	"board_cp": ["kaiju_eval_weights.*.board_cp", "kaiju_eval_weights.*.cp_pressure", "tag_scores.boosts_cp"],
	"threat": ["kaiju_eval_weights.*.rage", "kaiju_eval_weights.*.threat_margin", "tag_scores.boosts_threat"],
	"zone_delta": ["kaiju_eval_weights.*.zone_progress", "kaiju_eval_weights.*.zone_diff", "early_invasion_zone_threshold"],
	"card_advantage": ["kaiju_eval_weights.*.hand_diff", "tag_scores.draws_cards"],
	"rage_gained": ["kaiju_eval_weights.*.rage", "kaiju_eval_weights.*.latent_rage"],
	"counters_landed": ["kaiju_eval_weights.*.counter_them_bonus", "kaiju_eval_weights.*.cp_pressure"],
	"counters_suffered": ["kaiju_eval_weights.*.countered_penalty", "kaiju_eval_weights.*.opp_cp_growth", "kaiju_eval_weights.*.threat_margin"],
	"invade_steps": ["kaiju_eval_weights.*.zone_progress", "kaiju_eval_weights.*.counter_retreat_penalty"],
	"destroys_inflicted": ["tag_scores.destroys_zone"],
}

const PHASES: Array[String] = ["early", "mid", "late"]
const PHASE_METRICS: Array[String] = [
	"zone_delta", "board_cp", "threat", "card_advantage", "rage_gained",
	"invade_steps", "counters_landed", "counters_suffered", "destroys_inflicted",
]


## One game → {file, seed, mode, bot_difficulty, winner_id, total_turns,
## per_turn: [...], phases: {early/mid/late: {p0: {...means}, p1: {...}}}}.
static func analyze_game(replay: Dictionary, id_to_card: Callable) -> Dictionary:
	var snapshots: Array = replay.get("snapshots", [])
	var turns: Dictionary = {} # turn_number -> {first, last, tokens: []}
	var turn_order: Array[int] = []
	for snap in snapshots:
		var t: int = snap.get("turn_number", 0)
		if not turns.has(t):
			turns[t] = {"first": snap, "last": snap, "tokens": []}
			turn_order.append(t)
		turns[t]["last"] = snap
		turns[t]["tokens"].append_array(snap.get("log_lines", []))

	var per_turn: Array[Dictionary] = []
	var max_zone_seen: int = 1
	for t in turn_order:
		var first: Dictionary = turns[t]["first"]
		var last: Dictionary = turns[t]["last"]
		var tokens: Array = turns[t]["tokens"]
		for pid in range(2):
			max_zone_seen = maxi(max_zone_seen, int(last["players"][pid].get("monster_zone", 1)))
		var entry := {
			"turn": t,
			"actor": int(first.get("current_player_id", 0)),
			"phase": KaijuEvaluator.phase_key(t, max_zone_seen),
			"players": [],
		}
		for pid in range(2):
			var pf: Dictionary = first["players"][pid]
			var pl: Dictionary = last["players"][pid]
			var board_cards: int = 0
			var board_cp: int = 0
			for zone_stack in pl.get("zones", []):
				if zone_stack is Array and not zone_stack.is_empty():
					board_cards += 1
					var top: Dictionary = id_to_card.call(str(zone_stack[-1]))
					board_cp += int(top.get("counter_power", 0))
			var monster: Dictionary = id_to_card.call(str(pl.get("current_monster", "")))
			var opp: Dictionary = last["players"][1 - pid]
			entry["players"].append({
				"zone": int(pl.get("monster_zone", 1)),
				"zone_delta": int(pl.get("monster_zone", 1)) - int(pf.get("monster_zone", 1)),
				"rank": int(monster.get("rank", 0)),
				"rage_end": int(pl.get("rage", 0)),
				"hand_count": int(pl.get("hand_count", 0)),
				"board_cards": board_cards,
				"board_cp": board_cp,
				"threat": int(monster.get("threat_level", 0)) + int(pl.get("rage", 0)) * 5000,
				"card_advantage": int(pl.get("hand_count", 0)) + board_cards \
						- int(opp.get("hand_count", 0)) - _board_card_count(opp),
				"rage_gained": _count_tokens(tokens, "gained_rage", pid),
				"invade_steps": _invade_steps(tokens, pid),
				"counters_landed": _count_tokens(tokens, "counter_succeeded", pid),
				"counters_suffered": _counters_suffered(tokens, pid),
				"destroys_inflicted": _destroys(tokens, pid),
				"counter_events": _counter_events(tokens, pid),
			})
		per_turn.append(entry)

	return {
		"file": replay.get("label", ""),
		"seed": int(replay.get("game_seed", 0)),
		"mode": str(replay.get("mode", "")),
		"bot_difficulty": str(replay.get("bot_difficulty", "")),
		"winner_id": int(replay.get("winner_id", -1)),
		"win_reason": str(replay.get("win_reason", "")),
		"total_turns": int(replay.get("total_turns", 0)),
		"per_turn": per_turn,
		"phases": _phase_summary(per_turn),
	}


## Cross-game aggregate: win rates, per-phase winner-minus-loser deltas, and
## ranked tuning signals with suggested BotConfig knobs.
static func aggregate(games: Array) -> Dictionary:
	var wins: Dictionary = {"p0": 0, "p1": 0, "draw": 0}
	var reasons: Dictionary = {}
	var total_turns: int = 0
	# phase -> metric -> {winner: [values], loser: [values]}
	var buckets: Dictionary = {}
	for phase in PHASES:
		buckets[phase] = {}
		for m in PHASE_METRICS:
			buckets[phase][m] = {"winner": [], "loser": []}

	for game in games:
		var w: int = game["winner_id"]
		total_turns += int(game["total_turns"])
		if w == 0:
			wins["p0"] += 1
		elif w == 1:
			wins["p1"] += 1
		else:
			wins["draw"] += 1
		var reason: String = game.get("win_reason", "")
		reasons[reason] = int(reasons.get(reason, 0)) + 1
		if w < 0:
			continue
		for phase in PHASES:
			var summary: Dictionary = game["phases"].get(phase, {})
			if summary.is_empty():
				continue
			for m in PHASE_METRICS:
				buckets[phase][m]["winner"].append(float(summary["p%d" % w].get(m, 0.0)))
				buckets[phase][m]["loser"].append(float(summary["p%d" % (1 - w)].get(m, 0.0)))

	var per_phase: Dictionary = {}
	var signals: Array[Dictionary] = []
	for phase in PHASES:
		per_phase[phase] = {}
		for m in PHASE_METRICS:
			var w_avg := _mean(buckets[phase][m]["winner"])
			var l_avg := _mean(buckets[phase][m]["loser"])
			per_phase[phase][m] = {
				"winner_avg": w_avg, "loser_avg": l_avg,
				"winner_minus_loser": w_avg - l_avg,
			}
			signals.append({
				"metric": m, "phase": phase,
				"winner_minus_loser": w_avg - l_avg,
				"suggested_knobs": KNOB_MAP.get(m, []),
			})
	signals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(a["winner_minus_loser"]) > absf(b["winner_minus_loser"]))

	return {
		"schema_version": SCHEMA_VERSION,
		"source": {"game_count": games.size()},
		"win_rate": {
			"p0": float(wins["p0"]) / maxi(games.size(), 1),
			"p1": float(wins["p1"]) / maxi(games.size(), 1),
			"draws": wins["draw"],
		},
		"avg_turns": float(total_turns) / maxi(games.size(), 1),
		"win_reasons": reasons,
		"per_phase": per_phase,
		"signals": signals,
		"knob_map": KNOB_MAP,
	}


static func to_markdown(report: Dictionary, games: Array) -> String:
	var md: Array[String] = []
	var wr: Dictionary = report["win_rate"]
	md.append("# Replay Stats Report")
	md.append("")
	md.append("Games: %d · Avg turns: %.1f · P1 win rate: %.0f%% · P2 win rate: %.0f%%" % [
		report["source"]["game_count"], report["avg_turns"], wr["p0"] * 100.0, wr["p1"] * 100.0])
	md.append("")
	md.append("## Win reasons")
	md.append("")
	for reason in report["win_reasons"]:
		md.append("- %s: %d" % [reason, report["win_reasons"][reason]])
	md.append("")
	md.append("## Winner vs loser by phase (winner mean − loser mean, per turn)")
	md.append("")
	md.append("| Metric | Early | Mid | Late |")
	md.append("|---|---|---|---|")
	for m in PHASE_METRICS:
		var cells: Array[String] = []
		for phase in PHASES:
			cells.append("%+.2f" % report["per_phase"][phase][m]["winner_minus_loser"])
		md.append("| %s | %s |" % [m, " | ".join(cells)])
	md.append("")
	md.append("## Top tuning signals")
	md.append("")
	var shown: int = 0
	for sig in report["signals"]:
		if shown >= 10:
			break
		md.append("%d. **%s / %s** (Δ %+0.2f) → knobs: `%s`" % [shown + 1,
				sig["phase"], sig["metric"], sig["winner_minus_loser"],
				"`, `".join(PackedStringArray(sig["suggested_knobs"]))])
		shown += 1
	md.append("")
	md.append("## Games")
	md.append("")
	md.append("| # | Winner | Turns | Reason | Difficulty |")
	md.append("|---|---|---|---|---|")
	for i in range(games.size()):
		var g: Dictionary = games[i]
		md.append("| %d | P%d | %d | %s | %s |" % [i + 1, g["winner_id"] + 1,
				g["total_turns"], g["win_reason"], g["bot_difficulty"]])
	md.append("")
	return "\n".join(md)


# --- Internals ---

## Per-phase per-player means over the turns in that phase.
static func _phase_summary(per_turn: Array[Dictionary]) -> Dictionary:
	var summary: Dictionary = {}
	for phase in PHASES:
		var rows: Array[Dictionary] = []
		for entry in per_turn:
			if entry["phase"] == phase:
				rows.append(entry)
		if rows.is_empty():
			continue
		var phase_block: Dictionary = {"turns": rows.size()}
		for pid in range(2):
			var means: Dictionary = {}
			for m in PHASE_METRICS:
				var values: Array = []
				for entry in rows:
					values.append(float(entry["players"][pid].get(m, 0.0)))
				means[m] = _mean(values)
			phase_block["p%d" % pid] = means
		summary[phase] = phase_block
	return summary


static func _board_card_count(player: Dictionary) -> int:
	var n: int = 0
	for zone_stack in player.get("zones", []):
		if zone_stack is Array and not zone_stack.is_empty():
			n += 1
	return n


static func _count_tokens(tokens: Array, type: String, pid: int) -> int:
	var n: int = 0
	for tok in tokens:
		if tok.get("type", "") == type and int(tok.get("player_id", -1)) == pid:
			n += 1
	return n


static func _invade_steps(tokens: Array, pid: int) -> int:
	var steps: int = 0
	for tok in tokens:
		if tok.get("type", "") == "invaded" and int(tok.get("player_id", -1)) == pid:
			steps += 2 if tok.get("is_step2", false) else 1
	return steps


## counter_succeeded.player_id is the COUNTERER; the countered player is the
## other one.
static func _counters_suffered(tokens: Array, pid: int) -> int:
	var n: int = 0
	for tok in tokens:
		if tok.get("type", "") == "counter_succeeded" and int(tok.get("player_id", -1)) == 1 - pid:
			n += 1
	return n


static func _destroys(tokens: Array, pid: int) -> int:
	var n: int = 0
	for tok in tokens:
		if tok.get("type", "") == "effect_destroyed_card" and int(tok.get("source_player_id", -1)) == pid:
			n += 1
	return n


## Full counter events involving pid as the counterer, with margins — the
## replay's only source of effect-inclusive threat/CP values.
static func _counter_events(tokens: Array, pid: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for tok in tokens:
		var type: String = tok.get("type", "")
		if type != "counter_succeeded" and type != "counter_failed":
			continue
		if int(tok.get("player_id", -1)) != pid:
			continue
		events.append({
			"success": type == "counter_succeeded",
			"total_cp": int(tok.get("total_cp", 0)),
			"threat": int(tok.get("threat", 0)),
			"threat_rage": int(tok.get("threat_rage", 0)),
			"threat_effects": int(tok.get("threat_effects", 0)),
			"margin": int(tok.get("total_cp", 0)) - int(tok.get("threat", 0)),
		})
	return events


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for v in values:
		total += float(v)
	return total / values.size()
