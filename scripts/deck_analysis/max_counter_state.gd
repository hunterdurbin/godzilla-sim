class_name MaxCounterState
extends RefCounted

## Synthetic counter-phase board for deck analysis: a real GameState wired to
## a real EffectHandler/ActionHandler so counter power is read back from
## CounterResolver.compute_counter_numbers — never hand-summed. The optimizer
## (MaxCounterOptimizer) mutates the board via apply() and asks evaluate()
## for the engine's own number.
##
## Perspective: player 0 counters on their OWN turn (TurnManager resolves the
## counter phase with the countering player as current player), so own-turn
## conditionals legitimately apply. The opponent board is empty, so
## engagement restriction / immunity / prevention all no-op.
##
## Best-case assumptions baked into the state (see deck_analysis/README.md):
## late game (turn 10), every unplaced main-deck copy in the discard pile,
## rage set by the caller, monster stack built from the deck's lower ranks.

var state: GameState
var effect_handler: EffectHandler
var action_handler: ActionHandler

## Every main-deck card instance (battle + strategy + rage), used to rebuild
## the discard pile as "everything not on the board" after each apply().
var _main_pool: Array[Dictionary] = []
## The deck's monster instances, used for current_monster / monster_stack /
## monster_deck reconstruction.
var _monster_pool: Array[Dictionary] = []


func _init(main_cards: Array[Dictionary], monster_cards: Array[Dictionary],
		strategy_zone_count: int = 2) -> void:
	_main_pool = main_cards
	_monster_pool = monster_cards
	state = GameState.new()
	state.current_player_id = 0
	state.current_phase = CardEnums.GamePhase.COUNTER
	state.turn_number = 10
	# "Assume 3rd strategy zone" (EBP03-013): grow the arrays exactly like
	# ebp03_013.gd on_enter does — the array size IS the zone count. No
	# signal emit; this state is synthetic and never rendered live.
	var player: PlayerState = state.players[0]
	while player.strategy_zones.size() < strategy_zone_count:
		player.strategy_zones.append({})
		player.strategy_zone_turn_placed.append(0)
		player.strategy_zone_stacks.append([])
	# Same wiring as tests/fixtures/states.gd make_session, minus GameEvents —
	# compute_counter_numbers and the CP queries never touch the event bus.
	effect_handler = EffectHandler.new()
	effect_handler.setup(state, PlayerInput.new())
	action_handler = ActionHandler.new()
	action_handler.effect_handler = effect_handler
	effect_handler.action_handler = action_handler


## Rewrite the whole player-0 board from an assignment dict:
##   monster: Dictionary ({} = keep zone block at monster_zone but no effect)
##   monster_zone: int 1-8
##   zones: Array of 8 entries, each {} or a card dict (placed as zone top)
##   strategies: Array with one entry per strategy zone (2, or 3 when
##     constructed with strategy_zone_count 3), each {} or a strategy card
##   rage: int
##   opp_monster_zone: int 1-8 (optional; opponent stays monster-less — CP
##     effects like EBP02-016 only read the zone int)
##   unders: Dictionary zone_idx -> card (optional; one card tucked under
##     that zone's top — buried cards are data only, their effects inactive)
##   monster_stack: Array (optional; a live caller's REAL stack, used verbatim
##     instead of the synthesized best-case one — see KaijuCounterOracle)
## Unplaced main-pool copies land in the discard pile (late-game best case);
## tokens are not in the pool, so they never pollute the discard.
func apply(assignment: Dictionary) -> void:
	var player: PlayerState = state.players[0]
	player.current_monster = assignment.get("monster", {})
	player.monster_zone = assignment.get("monster_zone", 1)
	player.rage = assignment.get("rage", 0)
	state.players[1].monster_zone = assignment.get("opp_monster_zone", 1)

	if assignment.has("monster_stack"):
		# Live-board passthrough: the caller's actual stack, so stack
		# conditionals read the real match state.
		var stack_in: Array[Dictionary] = []
		stack_in.assign(assignment["monster_stack"])
		player.monster_stack = stack_in
		player.monster_deck = [] as Array[Dictionary]
	else:
		# Monster stack: the deck's lower-rank monsters, descending — genuinely
		# reachable via normal rank-up, so stack conditionals are honestly true.
		var chosen_rank: int = player.current_monster.get("rank", 0)
		var stack: Array[Dictionary] = []
		var remaining: Array[Dictionary] = []
		for m in _monster_pool:
			if not player.current_monster.is_empty() and m["id"] == player.current_monster["id"]:
				continue
			if m.get("rank", 0) < chosen_rank:
				stack.append(m)
			else:
				remaining.append(m)
		stack.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.get("rank", 0) > b.get("rank", 0))
		player.monster_stack = stack
		player.monster_deck = remaining

	var placed_ids := {}
	var zones: Array = assignment.get("zones", [])
	var unders: Dictionary = assignment.get("unders", {})
	for i in range(8):
		player.zones[i] = []
		var card: Dictionary = zones[i] if i < zones.size() else {}
		if not card.is_empty():
			player.push_zone_card(i, card)
			placed_ids[card["id"]] = true
			var under: Dictionary = unders.get(i, {})
			if not under.is_empty():
				# Appended = the get_cards_under_top slot (index 1).
				player.zones[i].append(under)
				placed_ids[under["id"]] = true

	var strategies: Array = assignment.get("strategies", [])
	for i in range(player.strategy_zones.size()):
		var card: Dictionary = strategies[i] if i < strategies.size() else {}
		player.strategy_zones[i] = card
		if not card.is_empty():
			placed_ids[card["id"]] = true

	var discard: Array[Dictionary] = []
	for card in _main_pool:
		if not placed_ids.has(card["id"]):
			discard.append(card)
	player.discard_pile = discard
	player.hand = [] as Array[Dictionary]
	player.main_deck = [] as Array[Dictionary]


## The engine's own counter total for the currently applied board.
func evaluate() -> int:
	var numbers: Dictionary = action_handler.counter.compute_counter_numbers(state)
	return numbers["total_cp"]


## Attribution data for the preview modal, read from the same queries the
## live board HUD uses. zone_mods[i] sums each zone's ModifierBreakdown.
func breakdown() -> Dictionary:
	var queries: EffectQueries = effect_handler.queries
	var zone_mods: Array[int] = queries.get_zone_cp_modifiers(0)
	var zone_cp: Array[int] = []
	var player: PlayerState = state.players[0]
	for i in range(8):
		var top := player.get_zone_top_card(i)
		var base: int = top.get("counter_power", 0)
		zone_cp.append((base + zone_mods[i]) if not top.is_empty() else 0)
	return {
		"total_cp": evaluate(),
		"zone_mods": zone_mods,
		"zone_cp": zone_cp,
		"monster_cp_mod": queries.get_monster_cp_modifier(0),
		"strategy_cp_mods": queries.get_strategy_cp_modifiers(0),
	}


## Break the RefCounted cycles (same contract as every engine-stack owner —
## see the match-teardown rule in CLAUDE.md). Idempotent.
func teardown() -> void:
	if action_handler:
		action_handler.teardown()
	if effect_handler:
		effect_handler.teardown()
	action_handler = null
	effect_handler = null
	state = null
