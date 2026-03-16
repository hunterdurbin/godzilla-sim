class_name BotCombo
extends RefCounted

## Base class for bot combo detection. Each combo subclass implements check()
## to detect a specific multi-card win path and returns a standardized plan dict.
##
## Plan dictionary format:
##   "combo_name": String           -- for logging
##   "state": "full" | "partial"    -- full = all pieces in hand, partial = some in deck
##   "viability": int               -- score bonus for full state (0-150)
##   "reserved_indices": Array[int] -- hand indices this combo claims (protected from
##                                     discard, rage, invasion, and penalized in scoring)
##   "boosted_indices": Array[int]  -- subset that get score boost (full only)
##   "monster_play_rules": Dictionary -- see get_monster_play_rules()
##
## Monster play rules:
##   "skip_all": bool       -- skip all monster plays this decision
##   "force_play_idx": int  -- play exactly this monster if playable (-1 = none)
##   "exclude_idx": int     -- filter this monster from normal plays (-1 = none)

var combo_name: String = ""
var enabled: bool = false
var full_min_bonus: int = 100
var partial_penalty: int = 100


func check(_player: PlayerState, _opponent: PlayerState, _bot) -> Dictionary:
	## Override: detect combo, return plan dict or {} if not viable.
	return {}


func get_monster_play_rules(plan: Dictionary, _player: PlayerState, _bot) -> Dictionary:
	## Override: compute monster play rules for this decision frame.
	return plan.get("monster_play_rules", {})


func should_suppress_invasion(plan: Dictionary, player: PlayerState, opponent: PlayerState) -> bool:
	## Override: return true to suppress non-win invasion this decision frame.
	## Default: no suppression (reserved indices are still excluded from searches).
	return false


func get_invasion_preference(plan: Dictionary, player: PlayerState, opponent: PlayerState) -> Dictionary:
	## Override: return invasion guidance for combo-aware invasion targeting.
	## Keys: preferred_steps (1 or 2, 0=no pref), max_zone (-1=no limit),
	##        target_zone (-1=no target).
	return {"preferred_steps": 0, "max_zone": -1, "target_zone": -1}


func adjust_card_score(plan: Dictionary, hand_idx: int, base_score: int,
		player: PlayerState, opponent: PlayerState) -> int:
	## Override: return context-aware score adjustment for a card.
	## Default delegates to get_score_adjustment() for backward compatibility.
	return base_score + get_score_adjustment(plan, hand_idx)


func get_execution_action(plan: Dictionary, valid_actions: Array,
		player: PlayerState, opponent: PlayerState, bot) -> Array:
	## Override: when combo pieces are playable, return the next action in sequence.
	## Returns [action_type, params] or [] if no combo action to take.
	return []


func get_rankup_bonus(plan: Dictionary, monster: Dictionary,
		player: PlayerState, opponent: PlayerState, bot) -> int:
	## Override: return score bonus for choosing this monster during rank-up.
	## Positive = prefer, negative = avoid, 0 = no opinion.
	return 0


func get_battle_zone_avoidance(plan: Dictionary, player: PlayerState) -> Array[int]:
	## Override: return 0-indexed zones where battle cards should NOT be placed
	## (bot's monster will crush them during combo execution).
	return []


func get_score_adjustment(plan: Dictionary, hand_idx: int) -> int:
	## Return score adjustment for a card at hand_idx.
	var reserved: Array = plan.get("reserved_indices", [])
	var boosted: Array = plan.get("boosted_indices", [])
	if plan.get("state") == "full" and hand_idx in boosted:
		return maxi(plan.get("viability", 0), full_min_bonus)
	elif hand_idx in reserved:
		return -partial_penalty
	return 0
