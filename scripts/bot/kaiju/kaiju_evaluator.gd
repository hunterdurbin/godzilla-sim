class_name KaijuEvaluator
extends RefCounted

## End-of-turn state evaluation for the KAIJU planner. A weighted sum of
## named features; the weights live in BotConfig.kaiju_eval_weights per game
## phase so the replay-tuning loop (scripts/tools/replay_stats/) can adjust
## them without code changes.
##
## Counter/End phases are never rolled out — their expected outcome is folded
## in analytically here (counter margins, retreat, end-phase advance), using
## the same math as CounterResolver.compute_counter_numbers.

const WIN_SCORE: float = 1e9
## Soft terminal: being counterable while unable to rank up is a loss next
## counter phase unless the board changes. Large, but below WIN_SCORE so a
## found win still dominates.
const COUNTER_DEATH_PENALTY: float = 1e6

var config: BotConfig


func _init(cfg: BotConfig) -> void:
	config = cfg


## Game phase for weight selection. Latched: callers pass the high-water mark
## of the max monster zone EITHER player has reached this game (monsters move
## back when countered, but the game never returns to an earlier phase).
static func phase_key(turn_number: int, max_zone_seen: int) -> String:
	if max_zone_seen >= 7 or turn_number >= 14:
		return "late"
	if max_zone_seen >= 4 or turn_number >= 5:
		return "mid"
	return "early"


func evaluate(rollout: KaijuRollout, pid: int, phase: String) -> float:
	var win: int = rollout.winner()
	if win == pid:
		return WIN_SCORE
	if win >= 0:
		return -WIN_SCORE

	var gs: GameState = rollout.state()
	var q: EffectQueries = rollout.queries()
	var re: RulesEngine = rollout.rules()
	var p: PlayerState = gs.players[pid]
	var o: PlayerState = gs.players[1 - pid]
	var w: Dictionary = config.kaiju_eval_weights.get(phase, config.kaiju_eval_weights["mid"])
	var score: float = 0.0

	# --- Progress / material ---
	score += w["zone_progress"] * p.monster_zone
	score += w["zone_diff"] * (p.monster_zone - o.monster_zone)
	score += w["rank"] * p.current_monster.get("rank", 1)
	score += w["rage"] * p.rage
	score += w["latent_rage"] * _monster_cards_in_hand(p)
	score += w["hand_diff"] * (p.hand.size() - o.hand.size())
	score += w["board_cp"] * _defensive_board_cp(q, pid, w["fragile_cp_discount"])

	# --- Upcoming counter phase (OUR turn): WE counter THEM when our board
	# CP clears their threat (rule 5.15: current player counters opponent).
	# Deterministic — both numbers are public. A success retreats their
	# monster and burns one of their finite rank-ups; if they can't rank up,
	# it wins the game outright.
	var our_cp: int = _effective_counter_cp(q, p)
	var their_threat: int = q.get_effective_threat_level(1 - pid)
	# Continuous pressure gradient so the search values every CP step toward
	# a counter, not just the moment it lands.
	score += w["cp_pressure"] * clampf(our_cp - their_threat, -15000.0, 15000.0)
	if not q.is_counter_prevented(1 - pid, our_cp) and our_cp >= their_threat:
		if not re.can_opponent_rank_up(o):
			return WIN_SCORE * 0.5 # counter victory resolves this counter phase
		score += w["counter_them_bonus"]

	# Rank-ups are lives: each forced rank-up from a counter burns one, and
	# hitting the cap makes the next counter lethal. Graduated so the search
	# prices rank-life before the death cliff.
	score += w["rankups_left"] * mini(_rankups_left(p), 2)

	# --- THEIR next turn's counter phase: they counter US. Our rage-boosted
	# threat persists until our own next start phase, but their board CP will
	# have grown by a main phase of plays first. Battle-card rank playability
	# follows OUR monster's zone number, so advancing unlocks their hand:
	# growth ≈ hand size × CP-per-card × fraction of ranks our zone unlocks.
	var growth: float = o.hand.size() * w["opp_cp_growth"] * clampf(p.monster_zone / 8.0, 0.0, 1.0)
	var opp_cp: int = _effective_counter_cp(q, o) + int(growth)
	var our_threat: int = q.get_effective_threat_level(pid)
	# Continuous defense gradient: every rage point moves us away from the
	# opponent's projected counter wall even before we're fully safe.
	score += w["threat_margin"] * clampf(our_threat - opp_cp, -15000.0, 15000.0)
	if not q.is_counter_prevented(pid, opp_cp) and opp_cp >= our_threat:
		# A successful counter always forces a rank-up, burning the finite
		# monster line — flat penalty on top of the margin/retreat terms.
		score -= w["countered_penalty"]
		var retreat_zone: int = ActionHandler.get_counter_retreat_zone(p.monster_zone)
		score -= w["counter_retreat_penalty"] * (p.monster_zone - retreat_zone)
		if not re.can_opponent_rank_up(p):
			score -= COUNTER_DEATH_PENALTY

	# --- Opponent threats under the info-visibility knob ---
	if not q.is_invasion_blocked(pid):
		score -= w["opp_invade_threat"] * _expected_opp_invade_steps(o)
	if not re.can_opponent_rank_up(o):
		# They lose to a single successful counter — strong incentive to press.
		score += w["opp_rankup_threat"]

	# --- Zone 8 endgame control ---
	if p.zone_has_battle_card(7) and o.monster_zone >= 6:
		score += w["zone8_defense"]
	if o.zone_has_battle_card(7) and p.monster_zone >= 6:
		score -= w["opp_zone8_block"]

	return score


## Immediate rank-up options in the monster deck (rule: next rank + shared
## trait) — the player's remaining "lives" against counters.
func _rankups_left(p: PlayerState) -> int:
	var next_rank: int = p.current_monster.get("rank", 1) + 1
	var cur_traits: Array = p.current_monster.get("traits", [])
	var n: int = 0
	for m in p.monster_deck:
		if m.get("rank") != next_rank:
			continue
		for t in m.get("traits", []):
			if t in cur_traits:
				n += 1
				break
	return n


func _monster_cards_in_hand(p: PlayerState) -> int:
	var n: int = 0
	for card in p.hand:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			n += 1
	return n


## Total effective CP a player brings to a counter attempt — mirrors
## CounterResolver.compute_counter_numbers.
func _effective_counter_cp(q: EffectQueries, counterer: PlayerState) -> int:
	return counterer.get_total_counter_power() \
			+ q.get_counter_power_modifier(counterer.player_id) \
			- q.get_engagement_restricted_cp(counterer.player_id)


## Sum of effective zone CP, discounting the share contributed by fragile
## sources (strategy-zone cards the opponent can destroy) via the
## modifier_breakdown data.
func _defensive_board_cp(q: EffectQueries, pid: int, discount: float) -> float:
	var total: float = 0.0
	var breakdown: Array = q.get_zone_cp_breakdown(pid)
	for zone_idx in range(8):
		var cp: int = q.get_effective_zone_cp(pid, zone_idx)
		if cp == 0:
			continue
		var fragile: int = 0
		for entry in breakdown[zone_idx]:
			if entry.get("src_loc", "") == "strategy":
				fragile += entry.get("amount", 0)
		total += cp - discount * maxf(0.0, fragile)
	return total


## Expected invasion steps available to the opponent next turn, by how much
## of their private information the config lets the planner see.
func _expected_opp_invade_steps(o: PlayerState) -> float:
	match config.kaiju_info_visibility:
		BotConfig.InfoVisibility.FULL:
			var best: float = 0.0
			for card in o.hand:
				best = maxf(best, minf(card.get("invasion_icon", 0), 2.0))
			return best
		BotConfig.InfoVisibility.DECKLIST:
			# Expectation over the hidden pool (hand ∪ deck, composition known).
			var pool: Array = o.hand + o.main_deck
			if pool.is_empty():
				return 0.0
			var icon_sum: float = 0.0
			for card in pool:
				icon_sum += minf(card.get("invasion_icon", 0), 2.0)
			return clampf(icon_sum / pool.size() * o.hand.size(), 0.0, 2.0)
		BotConfig.InfoVisibility.COUNTS:
			return 1.0 if not o.hand.is_empty() else 0.0
		_: # NONE — fixed pessimistic assumption
			return 2.0
