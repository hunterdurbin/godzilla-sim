class_name TriggerFilters
extends RefCounted

## Pure evaluation of the declarative TRIGGER_FILTERS DSL that effect scripts
## declare at class scope. Every function is static and takes its inputs
## explicitly — no game-state or active-effect reads — so the whole DSL is
## table-testable.
##
## Ambient values the callers must supply:
##  - is_own_turn: game_state.current_player_id == <watcher player id>
##  - active_effect_player_id: the player whose effect is currently executing
##    (-1 when no effect is active, i.e. a rules-based cause)
##
## An empty/missing filter dict always passes.


## Generic filter for delta triggers (on_rage_changed and friends).
## Keys: "phase", "own_turn", "direction" ("increase" | "decrease").
static func passes_basic(filter: Dictionary, current_phase: CardEnums.GamePhase, is_own_turn: bool, old_value: int, new_value: int) -> bool:
	if filter.is_empty():
		return true
	if filter.has("phase") and filter.phase != current_phase:
		return false
	if filter.has("own_turn") and filter.own_turn != is_own_turn:
		return false
	if filter.has("direction"):
		var dir: String = filter.direction
		if dir == "increase" and new_value <= old_value:
			return false
		if dir == "decrease" and new_value >= old_value:
			return false
	return true


## "on_enter" filter. Key: "played_from_hand" (true = only when played from
## hand; false = only when entered via an effect). `played_from_effect` is the
## card's entry-mode flag (set by trigger_enter).
static func passes_enter(filter: Dictionary, played_from_effect: bool) -> bool:
	if filter.is_empty():
		return true
	if filter.has("played_from_hand"):
		var from_hand: bool = not played_from_effect
		if filter.played_from_hand != from_hand:
			return false
	return true


## Shared "caused_by_opponent" gate (on_discard_from_hand, can_be_destroyed,
## protects_card_from_destruction, prevents_opponent_monster_move).
## true = pass only when the opponent's active effect is the cause; false =
## only when the watcher's own effect is. Rules-based causes (no active
## effect) match neither value.
static func passes_cause_gate(filter: Dictionary, active_effect_player_id: int, watcher_player_id: int) -> bool:
	if not filter.has("caused_by_opponent"):
		return true
	var by_effect: bool = active_effect_player_id >= 0
	var caused_by_opponent: bool = by_effect and active_effect_player_id != watcher_player_id
	var caused_by_self: bool = by_effect and active_effect_player_id == watcher_player_id
	if filter.caused_by_opponent and not caused_by_opponent:
		return false
	if not filter.caused_by_opponent and not caused_by_self:
		return false
	return true


## "on_discard_from_hand" filter. Keys: "caused_by_opponent", "own_turn".
static func passes_discard_from_hand(filter: Dictionary, is_own_turn: bool, active_effect_player_id: int, owner_player_id: int) -> bool:
	if filter.is_empty():
		return true
	if not passes_cause_gate(filter, active_effect_player_id, owner_player_id):
		return false
	if filter.has("own_turn") and filter.own_turn != is_own_turn:
		return false
	return true


## "on_phase_start" / "on_phase_end" filter. Keys: "phase", "own_turn".
static func passes_phase(filter: Dictionary, phase: CardEnums.GamePhase, is_own_turn: bool) -> bool:
	if filter.is_empty():
		return true
	if filter.has("phase") and filter.phase != phase:
		return false
	if filter.has("own_turn") and filter.own_turn != is_own_turn:
		return false
	return true


## "on_battle_card_played" filter.
## Keys: "own_turn", "played_by_opponent", "played_from_deck".
static func passes_battle_card_played(filter: Dictionary, is_own_turn: bool, played_by_opponent: bool, played_from_deck: bool) -> bool:
	if filter.is_empty():
		return true
	if filter.has("own_turn") and filter.own_turn != is_own_turn:
		return false
	if filter.has("played_by_opponent") and filter.played_by_opponent != played_by_opponent:
		return false
	if filter.has("played_from_deck") and filter.played_from_deck != played_from_deck:
		return false
	return true


## "on_hand_card_discarded" filter. Keys: "card_type" ("battle" | "strategy" |
## "monster"), "own_turn".
static func passes_hand_discarded(filter: Dictionary, is_own_turn: bool, discarded_card: Dictionary) -> bool:
	if filter.is_empty():
		return true
	if filter.has("card_type"):
		match String(filter.card_type):
			"battle":
				if not CardUtils.is_battle(discarded_card):
					return false
			"strategy":
				if not CardUtils.is_strategy(discarded_card):
					return false
			"monster":
				if not CardUtils.is_monster(discarded_card):
					return false
	if filter.has("own_turn") and filter.own_turn != is_own_turn:
		return false
	return true


## Generic own-turn-only filter (on_invasion_observed, can_monster_advance,
## can_monster_invade, and other turn-gated overrides). Key: "own_turn".
static func passes_own_turn(filter: Dictionary, is_own_turn: bool) -> bool:
	if filter.is_empty():
		return true
	if filter.has("own_turn") and filter.own_turn != is_own_turn:
		return false
	return true


## "can_be_destroyed" / "protects_card_from_destruction" filter.
## Keys: "caused_by_opponent", "own_turn".
static func passes_destruction_gate(filter: Dictionary, is_own_turn: bool, active_effect_player_id: int, watcher_player_id: int) -> bool:
	if filter.is_empty():
		return true
	if not passes_cause_gate(filter, active_effect_player_id, watcher_player_id):
		return false
	if filter.has("own_turn") and filter.own_turn != is_own_turn:
		return false
	return true


## "prevents_opponent_monster_move" filter. Keys: "own_turn", "caused_by_opponent".
static func passes_prevents_monster_move(filter: Dictionary, is_own_turn: bool, active_effect_player_id: int, watcher_player_id: int) -> bool:
	if filter.is_empty():
		return true
	if filter.has("own_turn") and filter.own_turn != is_own_turn:
		return false
	if not passes_cause_gate(filter, active_effect_player_id, watcher_player_id):
		return false
	return true


## "get_strategy_hand_rank_modifier" filter. Keys: "own_turn", "target_is_owner".
static func passes_strategy_hand_rank_modifier(filter: Dictionary, is_own_turn: bool, target_is_owner: bool) -> bool:
	if filter.is_empty():
		return true
	if filter.has("own_turn") and filter.own_turn != is_own_turn:
		return false
	if filter.has("target_is_owner") and filter.target_is_owner != target_is_owner:
		return false
	return true


## "on_card_returned_from_discard" filter. Keys: "own_turn", "returned_by_opponent".
static func passes_card_returned(filter: Dictionary, is_own_turn: bool, returned_by_opponent: bool) -> bool:
	if filter.is_empty():
		return true
	if filter.has("own_turn") and filter.own_turn != is_own_turn:
		return false
	if filter.has("returned_by_opponent") and filter.returned_by_opponent != returned_by_opponent:
		return false
	return true


## "on_ally_zone_card_destroyed" / "on_opponent_zone_card_destroyed" filter.
## Key: "column" ("monster" — destroyed zone must be in the watcher's monster
## column). `watcher_monster_zone` is the watcher's monster zone number (1-8;
## <= 0 means no anchor and the column filter fails). `is_cross_board`
## distinguishes ally (false, same side) vs opponent (true, cross-board).
static func passes_zone_destroyed(filter: Dictionary, watcher_monster_zone: int, zone_idx: int, is_cross_board: bool) -> bool:
	if filter.is_empty():
		return true
	if filter.has("column"):
		var anchor: int = watcher_monster_zone - 1
		if anchor < 0:
			return false
		match String(filter.column):
			"monster":
				var allowed: Array[int]
				if is_cross_board:
					allowed = CardEffect.get_opponent_column_zones(anchor)
				else:
					allowed = CardEffect.get_column_zones(anchor)
				if zone_idx not in allowed:
					return false
	return true
