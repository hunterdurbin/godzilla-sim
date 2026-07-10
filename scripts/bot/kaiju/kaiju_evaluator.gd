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

	# --- Deck-shape scaling (BotDeckProfile; empty profile = all factors 1.0).
	# A deck that cannot clear the opponent's zone-8 blocker or sustain
	# invasion tempo should not be paid full price for racing forward — and
	# should value the counter game more instead.
	var dp: Dictionary = config.kaiju_deck_profile
	var viability: float = float(dp.get("invasion_viability", 1.0))
	var clear_capability: float = float(dp.get("clear_capability", 1.0))
	# Saturating: any deck at viability >= 0.8 races at full speed — the
	# tempo/advance/style components keep even fully-capable decks below 1.0,
	# and cutting their zone terms measurably weakens them in racing matchups.
	# Only genuinely invasion-poor decks slow down and lean counter.
	var race_readiness: float = clampf(viability / 0.8, 0.0, 1.0)
	var zone_scale: float = lerpf(config.kaiju_viability_zone_floor, 1.0, race_readiness)
	var counter_scale: float = 1.0 + config.kaiju_low_viability_counter_boost * (1.0 - race_readiness)

	# --- Progress / material ---
	score += w["zone_progress"] * p.monster_zone * zone_scale
	score += w["zone_diff"] * (p.monster_zone - o.monster_zone) * zone_scale
	score += w["rank"] * p.current_monster.get("rank", 1)
	score += w["rage"] * p.rage
	score += w["latent_rage"] * _monster_cards_in_hand(p)
	# Our end phase is imminent from this end-of-main state and refills the
	# hand to 5 (rule 7.5.4), so a dumped hand is not card loss — project the
	# refill before the diff (this is what makes cycling weak cards into
	# fresh draws score fairly). The opponent's CURRENT hand is what fuels
	# their reply, so their side stays unprojected.
	var refill_ok: bool = not q.is_opponent_end_phase_draw_blocked(pid) and not p.main_deck.is_empty()
	var our_hand: int = p.hand.size()
	if refill_ok:
		our_hand = maxi(our_hand, 5)
	score += w["hand_diff"] * (our_hand - o.hand.size())
	score += w["board_cp"] * _defensive_board_cp(q, pid, w["fragile_cp_discount"])
	# Start-phase draws equal the OPPONENT monster's rank (rule 7.2.2): each
	# turn-pair we net (their rank − ours) cards. Prices the card-economy side
	# of rank, opposing the flat "rank" reward — early own rank-ups feed the
	# opponent's hand.
	score += w.get("draw_tempo", 0.0) \
			* (o.current_monster.get("rank", 1) - p.current_monster.get("rank", 1))
	# Bricked hand cards: battle cards whose rank exceeds the opponent
	# monster's zone by 2+ are dead weight (rule 8.2 gates playable rank on
	# THEIR zone; one zone away still counts as a near-future card). They
	# can't even be raged away (rage fodder must be monsters, rule 8.4) —
	# invasion costs and effect discards are the outlets, so the search
	# should prefer lines that spend them.
	score -= w.get("hand_bricks", 0.0) * _hand_bricks(p, o)

	# --- Upcoming counter phase (OUR turn): WE counter THEM when our board
	# CP clears their threat (rule 5.15: current player counters opponent).
	# Deterministic — both numbers are public. A success retreats their
	# monster and burns one of their finite rank-ups; if they can't rank up,
	# it wins the game outright.
	var our_cp: int = _effective_counter_cp(q, p)
	var their_threat: int = q.get_effective_threat_level(1 - pid)
	# Continuous pressure gradient so the search values every CP step toward
	# a counter, not just the moment it lands.
	score += w["cp_pressure"] * counter_scale * clampf(our_cp - their_threat, -15000.0, 15000.0)
	if not q.is_counter_prevented(1 - pid, our_cp) and our_cp >= their_threat:
		if not re.can_opponent_rank_up(o):
			return WIN_SCORE * 0.5 # counter victory resolves this counter phase
		score += w["counter_them_bonus"] * counter_scale
		# Race-aware counter restraint: countering while we lead the endgame
		# race retreats their monster (re-locking our battle-card ranks, rule
		# 8.2) and hands them a fresh higher-rank monster. Countering is
		# MANDATORY when CP >= threat (rule 7.4.3) — the only legal way to
		# avoid it is deployment restraint, so make crossing the threshold
		# net-negative here (weight exceeds counter_them_bonus). Scaled by
		# invasion viability: a deck that can't finish the race should still
		# take counter progress.
		var race_w: float = w.get("race_counter_restraint", 0.0) * viability
		if race_w != 0.0 and p.monster_zone >= 6 and o.monster_zone >= 6 \
				and p.monster_zone > o.monster_zone and _holds_invade_card(p):
			score -= race_w
	elif refill_ok:
		# Not countering this turn (CP short of their threat): each card below
		# a full hand is a fresh end-phase draw — the cycling filter value
		# that the neutral refill projection can't price.
		score += w.get("cycle_filter", 0.0) * clampf(5.0 - p.hand.size(), 0.0, 5.0)

	# Rank-ups are lives: each forced rank-up from a counter burns one, and
	# hitting the cap makes the next counter lethal. Graduated so the search
	# prices rank-life before the death cliff.
	# (A flat "last_rankup_liability" penalty at 0 rank-ups was tried and
	# reverted: no effect on ESD02's counter-attrition losses — those are
	# forced, not voluntary spends — and it cost tempo wins on ESD01.)
	score += w["rankups_left"] * mini(_rankups_left(p), 2)
	# Lives DIFFERENTIAL — win-condition proximity is relative: spending your
	# last rank-up while the opponent holds two is a catastrophic exchange
	# even when your own absolute count "only" dropped by one.
	score += w.get("rankups_diff", 0.0) * (mini(_rankups_left(p), 2) - mini(_rankups_left(o), 2))

	# --- THEIR next turn's counter phase: they counter US. Our rage-boosted
	# threat persists until our own next start phase, but their board CP will
	# have grown by a main phase of plays first. Battle-card rank playability
	# follows OUR monster's zone number, so advancing unlocks their hand:
	# growth ≈ hand size × CP-per-card × fraction of ranks our zone unlocks.
	# With an opponent profile (live games), the static per-card prior is
	# blended toward this opponent's MEASURED deployment rate.
	var op: Dictionary = config.kaiju_opponent_profile
	var trust: float = _profile_trust(op)
	var per_card: float = w["opp_cp_growth"]
	if trust > 0.0:
		per_card = lerpf(per_card, float(op.get("cp_per_card", per_card)), trust)
	var growth: float = o.hand.size() * per_card * clampf(p.monster_zone / 8.0, 0.0, 1.0)
	if trust > 0.0:
		# Hoarders (large steady hand) realize less of their hand per turn.
		growth *= lerpf(1.0, clampf(1.3 - 0.1 * float(op.get("hand_hoard", 3.0)), 0.7, 1.2), trust)
	# Counter aggression: how often this opponent actually lands counters,
	# vs a 0.25/turn neutral baseline.
	var counter_aggression: float = lerpf(1.0,
			clampf(float(op.get("counters_per_turn", 0.25)) / 0.25, 0.6, 1.6), trust)
	var opp_cp: int = _effective_counter_cp(q, o) + int(growth)
	var our_threat: int = q.get_effective_threat_level(pid)
	# Continuous defense gradient: every rage point moves us away from the
	# opponent's projected counter wall even before we're fully safe.
	score += w["threat_margin"] * counter_aggression * clampf(our_threat - opp_cp, -15000.0, 15000.0)
	if not q.is_counter_prevented(pid, opp_cp) and opp_cp >= our_threat:
		# A successful counter always forces a rank-up, burning the finite
		# monster line — flat penalty on top of the margin/retreat terms.
		score -= w["countered_penalty"] * counter_aggression
		var retreat_zone: int = ActionHandler.get_counter_retreat_zone(p.monster_zone)
		score -= w["counter_retreat_penalty"] * (p.monster_zone - retreat_zone)
		if not re.can_opponent_rank_up(p):
			score -= COUNTER_DEATH_PENALTY

	# --- Opponent threats under the info-visibility knob ---
	if not q.is_invasion_blocked(pid):
		var invade_factor: float = lerpf(1.0,
				clampf(float(op.get("invade_tempo", 0.8)) / 0.8
						+ 0.2 * float(op.get("early_invader", 0.0)), 0.6, 1.7), trust)
		score -= w["opp_invade_threat"] * invade_factor * _expected_opp_invade_steps(o)
	if not re.can_opponent_rank_up(o):
		# They lose to a single successful counter — strong incentive to press.
		score += w["opp_rankup_threat"]

	# --- Zone 8 endgame control ---
	if p.zone_has_battle_card(7) and o.monster_zone >= 6:
		score += w["zone8_defense"]
	if o.zone_has_battle_card(7) and p.monster_zone >= 6:
		# Being blocked at zone 8 costs more when the deck has no destruction
		# to clear the blocker (the invasion win is structurally capped).
		score -= w["opp_zone8_block"] \
				* (1.0 + config.kaiju_block_clear_scale * (1.0 - clear_capability))
		# Win-path availability (state-level, not deck-level): camped at z7+
		# with their zone 8 occupied and NO destruction answer in hand or on
		# board, the invasion win does not exist from this position — deep
		# camping is pure exposure (observed 3 games running).
		if p.monster_zone >= 7 and not _has_destroy_answer(rollout, p):
			score -= w.get("z8_dead_end", 0.0)

	# --- Combo assembly progress ---
	# Reward states where a combo line (e.g. shin) is held together: full
	# (all pieces in hand) counts the plan's viability, partial a fraction of
	# it — mirroring BotCombo.get_score_adjustment's full-vs-reserved split.
	# This is what lets the beam steer TOWARD assembling a combo instead of
	# spending its pieces as generic value.
	var combo_w: float = w.get("combo_progress", 0.0)
	if combo_w != 0.0 and rollout.policy != null and not rollout.policy._combos.is_empty():
		rollout.policy._active_combo_plan = {}
		rollout.policy._ensure_combo_plan()
		var plan: Dictionary = rollout.policy._active_combo_plan
		if not plan.is_empty():
			var progress: float = plan.get("viability", 0)
			if plan.get("state") != "full":
				progress *= 0.4
			score += combo_w * progress

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


## How much to trust the opponent profile: ramps with usable game count,
## capped at 0.8 so the static prior never fully vanishes. Empty profile → 0.
func _profile_trust(op: Dictionary) -> float:
	if op.is_empty():
		return 0.0
	return clampf((int(op.get("games", 0)) - KaijuOpponentProfile.MIN_GAMES + 1) / 5.0, 0.0, 0.8)


## Battle cards in hand that are unplayable now and not close to unlocking
## (rank > opponent monster zone + 1). Rank 7+ cards count double below the
## endgame — they realistically never unlock.
static func _hand_bricks(p: PlayerState, o: PlayerState) -> float:
	var bricks: float = 0.0
	for card in p.hand:
		if card.get("card_type") != CardEnums.CardType.BATTLE:
			continue
		var rank: int = int(card.get("rank", 0))
		if rank > o.monster_zone + 1:
			bricks += 2.0 if rank >= 7 and o.monster_zone < 6 else 1.0
	return bricks


## True if any card in hand or on our zones carries a destroys_zone effect —
## the state-level answer to the opponent's zone-8 blocker (effect lookups
## are registry-cached; cheap after the first evaluation).
func _has_destroy_answer(rollout: KaijuRollout, p: PlayerState) -> bool:
	var handler: EffectHandler = rollout.tm.effect_handler
	for card in p.hand:
		var effect := handler.get_effect(card)
		if effect and "destroys_zone" in effect.get_bot_tags():
			return true
	for zone_idx in range(8):
		var top: Dictionary = p.get_zone_top_card(zone_idx)
		if top.is_empty():
			continue
		var effect := handler.get_effect(top)
		if effect and "destroys_zone" in effect.get_bot_tags():
			return true
	return false


func _holds_invade_card(p: PlayerState) -> bool:
	for card in p.hand:
		if int(card.get("invasion_icon", 0)) >= 1:
			return true
	return false


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
