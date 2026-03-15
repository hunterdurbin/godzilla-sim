class_name BotConfig
extends RefCounted

## Holds all tunable bot parameters. Factory methods return difficulty presets.

enum Difficulty {EASY, NORMAL, HARD}

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

# Deck analysis
var playstyle_threshold: float = 0.6


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
	return c


static func from_difficulty(difficulty: Difficulty) -> BotConfig:
	match difficulty:
		Difficulty.EASY:
			return easy()
		Difficulty.HARD:
			return hard()
		_:
			return normal()
