class_name BotConfig
extends RefCounted

## Holds all tunable bot parameters. Factory methods return difficulty presets.

enum Difficulty {EASY, NORMAL, HARD, KAIJU}

## How much of the opponent's private information the planner may use.
## NONE: fixed pessimistic assumptions; COUNTS: hand/deck counts only;
## DECKLIST: counts + hidden-pool composition (hand ∪ deck, unordered);
## FULL: reads the opponent's actual hand and deck order.
enum InfoVisibility {NONE, COUNTS, DECKLIST, FULL}

# Timing
var action_delay: float = 0.5

# Playstyle override (-1 = auto-detect, 0=INVASION, 1=COUNTER, 2=BALANCED)
var forced_playstyle: int = -1

# Scoring
var base_play_score: int = 10
var cp_bonus_divisor: int = 1000
var playstyle_multiplier: int = 10

# Tag scores — base score for each bot tag (simple tags only)
var tag_scores: Dictionary = {
	"destroys_zone": 30,
	"boosts_cp": 20,
	"boosts_threat": 15,
	"draws_cards": 15,
	"disrupts_hand": 20,
	"blocks_zone": 15,
	"blocks_invade": 10,
	"searches_deck": 15,
	"advances_self": 20,
	"advances_opponent": 20,
	"weakens_opponent": 15,
	"heals_deck": 5,
	"mill_self": 10,
	"mill_opponent": 10,
	"evolves": 20,
	"plays_from_discard": 20,
	"evolution": 15,
}

# Situational tag bonuses — tag -> {condition_key -> bonus}
# Condition keys: "near_winning_z8_blocked", "opponent_zone_6_plus",
#                 "opponent_zone_5_plus", "near_winning"
var tag_situational_bonuses: Dictionary = {
	"destroys_zone": {"near_winning_z8_blocked": 50},
	"boosts_cp": {"opponent_zone_6_plus": 15},
	"blocks_invade": {"opponent_zone_5_plus": 20},
	"advances_self": {"near_winning": 15},
	"advances_opponent": {},
}

# Column/zone-dependent tag scoring
var zone_dependent_bonus: int = 10
var column_dependent_battle_base: int = 10
var column_dependent_battle_per_card: int = 3
var column_dependent_monster_bonus: int = 15

# Trigger score rules — Array of [trigger_names: Array, score: int]
# If any trigger in the group matches, the score is added once.
var trigger_score_rules: Array = [
	[["on_enter"], 10],
	[["get_counter_power_modifier", "get_field_cp_modifiers", "get_total_cp_modifier"], 15],
	[["get_threat_level_modifier"], 10],
	[["on_when_invading"], 5],
	[["on_phase_start"], 10],
	[["on_rage_changed", "on_opponent_rage_changed"], 10],
	[["on_monster_played"], 5],
	[["on_would_be_destroyed", "can_be_destroyed"], 10],
	[["get_engagement_restriction"], 15],
	[["prevents_opponent_invasion"], 5],
	[["get_blocked_opponent_zones"], 10],
	[["blocks_opponent_strategy_plays"], 10],
	[["get_counter_immunity_threshold"], 15],
	[["get_extra_end_phase_advance"], 15],
	[["get_opponent_field_rank_modifier"], 10],
]

# Trigger situational bonuses — [trigger_name, condition_key, bonus]
var trigger_situational_bonuses: Array = [
	["get_engagement_restriction", "opponent_zone_5_plus", 10],
	["prevents_opponent_invasion", "opponent_zone_5_plus", 15],
]

# Synergies
var enable_synergies: bool = true
var synergy_board_multiplier: float = 1.0
var synergy_hand_multiplier: float = 0.5
var synergy_deck_multiplier: float = 0.25

# Each entry: [tag_on_card, synergy_tag_on_board_or_deck, bonus]
var tag_synergies: Array = [
	["mill_self", "plays_from_discard", 15],
	["heals_deck", "evolution", 15],
	["evolves", "evolution", 20],
	["destroys_zone", "advances_self", 10],
	["advances_opponent", "boosts_threat", 10],
	["advances_opponent", "destroys_zone", 10],
	["boosts_threat", "weakens_opponent", 10],
	["weakens_opponent", "boosts_threat", 10],
	["searches_deck", "evolution", 10],
	["disrupts_hand", "destroys_zone", 10],
	["blocks_invade", "boosts_cp", 10],
]

# Invasion
var use_early_invasion: bool = true
var early_invasion_zone_threshold: int = 5
var zone_6_two_step_chance: float = 0.5
var balanced_can_invade: bool = true
var protect_two_step_cards: bool = true

# Zone selection
var use_zone_priority_table: bool = true
var destroy_zone_priority_near_win: Array[int] = [7, 2, 1, 0, 3, 4, 5, 6]
var consider_column_tags: bool = true
var overwrite_lowest_cp_when_full: bool = true

# Card selection
var evolution_require_cp_upgrade: bool = true
var choice_pick_mode: int = 2 # 0=first, 1=random, 2=last
var discard_priority: Array = ["monsters", "non_playable", "playable"]

# Monster sort bonuses
var monster_burst_match_bonus: int = 150000
var monster_rank_match_bonus: int = 100000
var monster_trait_bonus: int = 50000

# Activation check
var use_activation_check: bool = true
var unfulfilled_trigger_penalty: int = 20
var unfulfilled_destroy_penalty: int = 40

# Combos — list of combo names to enable (e.g., ["shin"])
var enabled_combos: Array[String] = []

# Deck analysis
var playstyle_threshold: float = 0.6

# --- KAIJU planner (turn-plan search) ---
# Inert unless use_planner is true; only the kaiju() preset enables it.
var use_planner: bool = false
var kaiju_info_visibility: int = InfoVisibility.COUNTS
var kaiju_beam_width: int = 6
var kaiju_max_depth: int = 6 # actions per turn incl. the terminal stop
var kaiju_node_budget: int = 400 # scratch-match expansions per deliberation
var kaiju_time_budget_ms: int = 250
var kaiju_battle_candidates: int = 4 # top-K battle cards per node
var kaiju_zone_candidates: int = 2 # top-K zones per battle card
var kaiju_strategy_candidates: int = 4
# Roll out a greedy opponent reply (their whole next turn, incl. their counter
# phase against us) at the top beam finalists and pick the plan by post-reply
# score. Catches one-turn opponent CP spikes the analytic model misses.
var kaiju_opponent_ply: bool = true
var kaiju_opponent_reply_actions: int = 10 # action cap per finalist reply
var kaiju_finalists: int = 4 # beam leaves re-scored with the opponent ply

# --- KAIJU deck / opponent profiles (planner-gated; inert elsewhere) ---
# Deck-shape profile set once per match by BotPlayer.analyze_deck() when
# use_planner (BotDeckProfile.compute). Empty = neutral (all evaluator scale
# factors 1.0).
var kaiju_deck_profile: Dictionary = {}
# Viability shaping scalars read by KaijuEvaluator (tunable like weights):
var kaiju_viability_zone_floor: float = 0.35 # zone terms scale lerp(floor, 1, viability)
var kaiju_low_viability_counter_boost: float = 0.35 # counter terms ×(1 + boost×(1−viability))
var kaiju_block_clear_scale: float = 0.5 # opp_zone8_block ×(1 + scale×(1−clear_capability))
# Live-only opponent-tendency profile (KaijuOpponentProfile, wired by
# game_session). Empty = disabled. NEVER set in headless sims — KAIJU seed
# determinism depends on it staying empty there.
var kaiju_opponent_profile: Dictionary = {}

# Phase-aware evaluation weights. Phases latch on the game's high-water mark
# (max monster zone either player has reached, or turn count) — see
# KaijuEvaluator.phase_key. Keys are feature names; the replay-tuning loop
# edits these values (see scripts/tools/replay_stats/).
var kaiju_eval_weights: Dictionary = {
	"early": {
		"zone_progress": 5.0,
		"zone_diff": 5.0,
		"rank": 12.0,
		"rage": 20.0,
		"latent_rage": 8.0,
		"hand_diff": 10.0,
		"board_cp": 0.008,
		"threat_margin": 0.002,
		"cp_pressure": 0.010,
		"rankups_left": 40.0,
		"rankups_diff": 30.0,
		"z8_dead_end": 0.0,
		"cycle_filter": 4.0,
		"countered_penalty": 120.0,
		"counter_retreat_penalty": 60.0,
		"counter_them_bonus": 120.0,
		"race_counter_restraint": 0.0,
		"draw_tempo": 4.0,
		"hand_bricks": 6.0,
		"opp_cp_growth": 1500.0,
		"opp_invade_threat": 15.0,
		"opp_rankup_threat": 10.0,
		"zone8_defense": 40.0,
		"opp_zone8_block": 30.0,
		"fragile_cp_discount": 0.15,
		"combo_progress": 0.5,
	},
	"mid": {
		"zone_progress": 25.0,
		"zone_diff": 30.0,
		"rank": 10.0,
		"rage": 18.0,
		"latent_rage": 6.0,
		"hand_diff": 10.0,
		"board_cp": 0.008,
		"threat_margin": 0.006,
		"cp_pressure": 0.012,
		"rankups_left": 60.0,
		"rankups_diff": 60.0,
		"z8_dead_end": 60.0,
		"cycle_filter": 3.0,
		"countered_penalty": 180.0,
		"counter_retreat_penalty": 90.0,
		"counter_them_bonus": 180.0,
		"race_counter_restraint": 300.0,
		"draw_tempo": 3.0,
		"hand_bricks": 8.0,
		"opp_cp_growth": 1800.0,
		"opp_invade_threat": 25.0,
		"opp_rankup_threat": 20.0,
		"zone8_defense": 80.0,
		"opp_zone8_block": 60.0,
		"fragile_cp_discount": 0.15,
		"combo_progress": 0.8,
	},
	"late": {
		"zone_progress": 70.0,
		"zone_diff": 45.0,
		"rank": 6.0,
		"rage": 12.0,
		"latent_rage": 2.0,
		"hand_diff": 8.0,
		"board_cp": 0.006,
		"threat_margin": 0.010,
		"cp_pressure": 0.012,
		"rankups_left": 120.0,
		"rankups_diff": 100.0,
		"z8_dead_end": 150.0,
		"cycle_filter": 2.0,
		"countered_penalty": 240.0,
		"counter_retreat_penalty": 140.0,
		"counter_them_bonus": 240.0,
		"race_counter_restraint": 420.0,
		"draw_tempo": 1.5,
		"hand_bricks": 10.0,
		"opp_cp_growth": 2000.0,
		"opp_invade_threat": 45.0,
		"opp_rankup_threat": 30.0,
		"zone8_defense": 160.0,
		"opp_zone8_block": 120.0,
		"fragile_cp_discount": 0.15,
		"combo_progress": 1.0,
	},
}


static func easy() -> BotConfig:
	var c := BotConfig.new()
	c.action_delay = 0.7
	# Scale all tag scores to 60%
	for key in c.tag_scores:
		c.tag_scores[key] = int(c.tag_scores[key] * 0.6)
	# Scale column/zone scores
	c.zone_dependent_bonus = int(c.zone_dependent_bonus * 0.6)
	c.column_dependent_battle_base = int(c.column_dependent_battle_base * 0.6)
	c.column_dependent_battle_per_card = int(c.column_dependent_battle_per_card * 0.6)
	c.column_dependent_monster_bonus = int(c.column_dependent_monster_bonus * 0.6)
	# Scale trigger scores
	for i in c.trigger_score_rules.size():
		c.trigger_score_rules[i] = [c.trigger_score_rules[i][0], int(c.trigger_score_rules[i][1] * 0.6)]
	# Scale situational bonuses
	for key in c.tag_situational_bonuses:
		var bonuses: Dictionary = c.tag_situational_bonuses[key].duplicate()
		for cond in bonuses:
			bonuses[cond] = int(bonuses[cond] * 0.6)
		c.tag_situational_bonuses[key] = bonuses
	for i in c.trigger_situational_bonuses.size():
		var entry: Array = c.trigger_situational_bonuses[i]
		c.trigger_situational_bonuses[i] = [entry[0], entry[1], int(entry[2] * 0.6)]
	# Disable synergies
	c.enable_synergies = false
	# No column logic
	c.consider_column_tags = false
	# No early invasion
	c.use_early_invasion = false
	# Random zone picks
	c.use_zone_priority_table = false
	# Always evolve (don't require CP upgrade)
	c.evolution_require_cp_upgrade = false
	# Pick first choice
	c.choice_pick_mode = 0
	# Don't protect 2-step cards
	c.protect_two_step_cards = false
	# No activation check
	c.use_activation_check = false
	return c


static func normal() -> BotConfig:
	return BotConfig.new()


static func hard() -> BotConfig:
	var c := BotConfig.new()
	c.action_delay = 0.3
	# Scale all tag scores to 130%
	for key in c.tag_scores:
		c.tag_scores[key] = int(c.tag_scores[key] * 1.3)
	# Scale column/zone scores
	c.zone_dependent_bonus = int(c.zone_dependent_bonus * 1.3)
	c.column_dependent_battle_base = int(c.column_dependent_battle_base * 1.3)
	c.column_dependent_battle_per_card = int(c.column_dependent_battle_per_card * 1.3)
	c.column_dependent_monster_bonus = int(c.column_dependent_monster_bonus * 1.3)
	# Scale trigger scores
	for i in c.trigger_score_rules.size():
		c.trigger_score_rules[i] = [c.trigger_score_rules[i][0], int(c.trigger_score_rules[i][1] * 1.3)]
	# Scale situational bonuses
	for key in c.tag_situational_bonuses:
		var bonuses: Dictionary = c.tag_situational_bonuses[key].duplicate()
		for cond in bonuses:
			bonuses[cond] = int(bonuses[cond] * 1.3)
		c.tag_situational_bonuses[key] = bonuses
	for i in c.trigger_situational_bonuses.size():
		var entry: Array = c.trigger_situational_bonuses[i]
		c.trigger_situational_bonuses[i] = [entry[0], entry[1], int(entry[2] * 1.3)]
	# Stronger synergy multipliers
	c.synergy_board_multiplier = 1.5
	c.synergy_hand_multiplier = 0.75
	c.synergy_deck_multiplier = 0.4
	# Stronger unfulfilled penalties
	c.unfulfilled_trigger_penalty = int(c.unfulfilled_trigger_penalty * 1.3)
	c.unfulfilled_destroy_penalty = int(c.unfulfilled_destroy_penalty * 1.3)
	# Aggressive invasion
	c.early_invasion_zone_threshold = 6
	c.zone_6_two_step_chance = 0.75
	# Combos
	c.enabled_combos = ["shin"]
	return c


static func kaiju() -> BotConfig:
	var c := hard()
	c.action_delay = 0.2
	c.use_planner = true
	return c


static func from_difficulty(difficulty: Difficulty) -> BotConfig:
	match difficulty:
		Difficulty.EASY:
			return easy()
		Difficulty.HARD:
			return hard()
		Difficulty.KAIJU:
			return kaiju()
		_:
			return normal()
