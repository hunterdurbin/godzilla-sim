class_name KaijuCounterOracle
extends RefCounted

## Bridges the bot to the deck-analysis optimizer (MaxCounterOptimizer):
## "what is the best-case total counter power I could still field, keeping my
## current board exactly as it is?" Converts live per-copy card instances to
## decklist entries, locks the live board via the optimizer's lock params,
## RNG-fences every run, and caches per board/deck composition.
##
## Knowledge model: the bot's OWN main-deck CONTENTS are fully inferable
## (it built the deck), so reading them is fair game — but the draw ORDER is
## not known and is never consulted: the pool is handed over as a multiset
## (see the optimizer's deck_order_known placeholder). This is unrelated to
## BotConfig.InfoVisibility, which governs the OPPONENT's hidden information.
##
## Determinism: optimizer runs consume the global RNG, so every call is
## fenced like KaijuPlanner deliberation — seed from the composition key,
## re-seed a derived value afterwards (distinct salt from the planner's).
## Holds no engine references: no cycles, no teardown contract of its own
## (each optimizer's teardown() is called before the run returns).

const _POST_FENCE_SALT: int = 0x51F0C0DE

var _cache: Dictionary = {}  # composition key -> total_cp
var _cache_turn: int = -1    # cache cleared when the turn changes


## Live per-copy instances -> sorted decklist entries ({card_number,
## quantity}), counted by base id. Sorting keeps the composition key (and so
## the RNG fence) stable regardless of instance order.
static func instances_to_entries(cards: Array) -> Array:
	var counts := {}
	for card in cards:
		if (card as Dictionary).is_empty():
			continue
		var base := CardUtils.base_id(card)
		counts[base] = counts.get(base, 0) + 1
	var bases: Array = counts.keys()
	bases.sort()
	var entries: Array = []
	for base in bases:
		entries.append({"card_number": base, "quantity": counts[base]})
	return entries


## Unconstrained ceiling: the deck's maximum fieldable counter power,
## regardless of the current board. Computed once per match (analyze_deck);
## robust to mid-match calls (stack monsters count toward the monster pool).
static func deck_ceiling(player: PlayerState) -> int:
	var monsters: Array = player.monster_deck.duplicate()
	monsters.append_array(player.monster_stack)
	if not player.current_monster.is_empty():
		monsters.append(player.current_monster)
	var monster_entries := instances_to_entries(monsters)
	var pool: Array = player.hand.duplicate()
	pool.append_array(player.main_deck)
	var main_entries := instances_to_entries(pool)
	var fence: int = hash(["kaiju_oracle_deck", monster_entries, main_entries])
	seed(fence)
	var optimizer := MaxCounterOptimizer.new()
	var out: Dictionary = optimizer.run(monster_entries, main_entries)
	optimizer.teardown()
	seed(hash([fence, _POST_FENCE_SALT]))
	return int(out.get("total_cp", 0))


## Best-case total CP the bot could still reach ON TOP of its current board:
## monster, fielded battle cards (plus one modeled under each), and fielded
## strategies are locked in place; the optimizer fills the free slots from
## the remaining main deck (+ hand when include_hand). Engine-evaluated lower
## bound — never an overstatement. Cached per composition, cleared per turn.
func max_remaining(gs: GameState, pid: int, include_hand: bool = true) -> int:
	var player: PlayerState = gs.players[pid]
	if gs.turn_number != _cache_turn:
		_cache.clear()
		_cache_turn = gs.turn_number

	var pool: Array = player.main_deck.duplicate()
	if include_hand:
		pool.append_array(player.hand)
	var main_entries := instances_to_entries(pool)

	var locked_zones := {}
	var locked_unders := {}
	var free_zone := false
	var monster_idx: int = player.monster_zone - 1
	for i in range(8):
		var stack: Array = player.zones[i]
		if i == monster_idx:
			# The optimizer forbids battle cards in the monster's zone (the
			# crush rule 11.3 destroys them); a transient occupant is simply
			# dropped from the estimate (conservative).
			continue
		if stack.is_empty():
			free_zone = true
			continue
		locked_zones[i] = stack[0]
		if stack.size() > 1:
			locked_unders[i] = stack[1]

	var locked_strategies := {}
	var free_strategy := false
	for i in range(player.strategy_zones.size()):
		var sz: Dictionary = player.strategy_zones[i]
		if sz.is_empty():
			free_strategy = true
		else:
			locked_strategies[i] = sz

	var key: int = hash([
		main_entries,
		_lock_key(locked_zones), _lock_key(locked_unders), _lock_key(locked_strategies),
		player.current_monster.get("id", ""), player.monster_zone, player.rage,
		gs.players[1 - pid].monster_zone, player.strategy_zones.size(),
		include_hand,
	])
	if _cache.has(key):
		return _cache[key]

	var params := {
		"locked_monster": player.current_monster,
		"monster_zone": player.monster_zone,
		"opp_monster_zone": gs.players[1 - pid].monster_zone,
		"rage": player.rage,
		"strategy_zone_count": player.strategy_zones.size(),
		"locked_zones": locked_zones,
		"locked_unders": locked_unders,
		"locked_strategies": locked_strategies,
		"monster_stack": player.monster_stack,
		# Constrained runs are cheap: one config (locked monster + zone),
		# no opp-zone sweep, no rage recheck — one finalist/pass suffices.
		# With nothing left to place, skip improvement entirely.
		"finalists": 1,
		"improve_passes": 1 if free_zone or free_strategy else 0,
	}
	var fence: int = hash([key, "kaiju_oracle"])
	seed(fence)
	var optimizer := MaxCounterOptimizer.new()
	var out: Dictionary = optimizer.run([], main_entries, params)
	optimizer.teardown()
	seed(hash([fence, _POST_FENCE_SALT]))

	var total: int = int(out.get("total_cp", 0))
	_cache[key] = total
	return total


## Deterministic hash ingredient for a lock dict (built in ascending index
## order, so iteration order is stable).
static func _lock_key(locked: Dictionary) -> Array:
	var key: Array = []
	for idx in locked:
		key.append([idx, locked[idx].get("id", "")])
	return key
