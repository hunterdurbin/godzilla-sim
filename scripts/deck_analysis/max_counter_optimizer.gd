class_name MaxCounterOptimizer
extends RefCounted

## Searches for the highest-counter-power board a decklist can field, with
## every candidate board evaluated by the real engine through
## MaxCounterState.evaluate() — the reported number is always read off a
## valid GameState, never hand-summed (a lower bound on the true maximum,
## never an overstatement).
##
## Search shape: for each (monster, monster_zone) config up to three greedy
## orders fill the 7 non-monster zones (best-solo-score-first, effectful-
## first, tokens-first; adjacent slots first), each scored as a full board
## (unders + strategies) with the best kept; then the top seeds get local
## improvement passes (replace from bench, relocate swaps, strategy swaps). Placement-conditional effects (adjacency, zone 8,
## columns) are caught by the relocate pass; the search runs at rage
## SEARCH_RAGE (rage assumed reachable) and the winner is re-checked at 0.
##
## Drive it with setup() then step() until it returns false — each step is
## one bounded unit of work so a UI caller can await a frame between steps.

## Token-generating effects (create_token_in_zone callers) the search can
## exploit. Hand-maintained: audit `grep -rl create_token scripts/effects/`
## when adding a set — the guard test in test_max_counter_optimizer.gd fails
## if a caller is missing here. Modes:
##   replace — generator destroys itself to play the token (either the copy
##             or its token may be fielded, never both)
##   extra   — tokens persist beside/after their generator; gate: the
##             generator must be in the deck ("monster" source = monster deck)
##   fill    — one play fills every empty zone (up to 7 candidates)
##   linked  — token is zone-locked and requires the generator on the board
const TOKEN_SOURCES := {
	"EBP02-077": {"token": "EBP02-T04", "mode": "replace", "per_copy": 1},
	"EBP02-020": {"token": "EBP02-T01", "mode": "fill", "count": 7},
	"EBP02-025": {"token": "EBP02-T02", "mode": "extra", "per_copy": 1, "source": "monster"},
	"EBP02-035": {"token": "EBP02-T02", "mode": "extra", "per_copy": 2, "source": "main"},
	"EBP04-012": {"token": "EBP02-T02", "mode": "extra", "per_copy": 3, "source": "monster"},
	"EBP02-052": {"token": "EBP02-T03", "mode": "extra", "per_copy": 1, "source": "monster"},
	"EBP02-053": {"token": "EBP02-T03", "mode": "extra", "per_copy": 1, "source": "monster"},
	"EBP02-054": {"token": "EBP02-T03", "mode": "extra", "per_copy": 2, "source": "monster"},
	"EBP02-057": {"token": "EBP02-T03", "mode": "extra", "per_copy": 2, "source": "monster"},
	"EBP04-026": {"token": "EBP02-T03", "mode": "extra", "per_copy": 3, "source": "monster"},
	"EBP04-067": {"token": "EBP04-T01", "mode": "linked", "per_copy": 1, "zone_lock": [2]},
}

## Cards whose CP effects need a card tucked UNDER them, and how that under
## card legally gets there (hand-maintained, like TOKEN_SOURCES — the guard
## test fails when a place_card_under_zone caller feeding a CP effect is
## missing). Buried cards are data only (their effects are inactive) and are
## consumed from the pool like any fielded card. One under max per zone —
## EBP03-051's per-under scaling is modeled capped at 1 (documented
## undercount). Sources:
##   discard  — the top's own trigger tucks a matching discard-pile card
##   play     — the under was played to the zone first, the top stacked on
##              it (stacks_on_play)
##   strategy — tucked from a strategy zone at counter-phase start, so it
##              occupied a slot then: strategy-unders + filled slots <= 2
## Independent of the listed source, an under also qualifies via EVOLUTION
## (_evolves_under): the under carries evolution_rank/evolution_trait
## covering the top's rank/traits, so the top was legally played onto it.
const STACK_SOURCES := {
	"EBP03-064": {"source": "discard", "filter": "battle"},
	"EBP01-026": {"source": "discard", "filter": "traits_all",
			"traits": [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.FEST]},
	"EBP03-051": {"source": "play", "filter": "trait",
			"trait": CardEnums.CardTrait.LITTLE_GODZILLA},
	"EBP04-043": {"source": "strategy", "filter": "invasion_icon", "value": 2},
}

## CardEffect virtuals that make a card's CP contribution effect-dependent;
## cards without any of these are interchangeable vanillas (printed CP only).
const CP_TRIGGERS := [
	"get_counter_power_modifier", "get_variable_counter_power",
	"get_field_cp_modifiers", "get_total_cp_modifier", "can_engage",
]

const SEARCH_RAGE := 10
const VANILLA_KEEP := 8       # interchangeable vanillas kept in the pool
const POOL_CAP := 24          # hard cap on battle+token candidates
const FINALISTS := 3          # configs that get improvement passes
const IMPROVE_PASSES := 3

var _mcs: MaxCounterState
var _main_cards: Array[Dictionary] = []
var _battle_pool: Array[Dictionary] = []
var _strategy_pool: Array[Dictionary] = []
var _monster_pool: Array[Dictionary] = []
var _configs: Array = []          # pending {monster, monster_zone}
var _seeded: Array = []           # {assignment, score}
var _finalists: Array = []
var _solo_cache: Dictionary = {}  # monster_zone -> {candidate_id: score}
var _phase: int = 0               # 0 seed, 1 improve, 2 done
var _result: Dictionary = {}

# User constraints (see setup params). 0 / -1 = unconstrained.
var _fixed_monster_zone: int = 0  # 0 = Any (loop 1-8)
var _fixed_opp_zone: int = 0      # 0 = Any (best-case sweep in _improve)
var _fixed_rage: int = -1         # -1 = Auto (search at SEARCH_RAGE, recheck 0)
var _strategy_zone_count: int = 2 # 3 = assume EBP03-013's expansion resolved


## params (all optional): monster_zone 0|1-8, opp_monster_zone 0|1-8,
## rage -1|0-10, strategy_zone_count 2|3 (3 assumes EBP03-013's expansion).
## Zero/-1 = unconstrained (v1 behavior).
func setup(monster_entries: Array, main_entries: Array, params: Dictionary = {}) -> void:
	_fixed_monster_zone = clampi(params.get("monster_zone", 0), 0, 8)
	_fixed_opp_zone = clampi(params.get("opp_monster_zone", 0), 0, 8)
	_fixed_rage = clampi(params.get("rage", -1), -1, SEARCH_RAGE)
	_strategy_zone_count = clampi(params.get("strategy_zone_count", 2), 2, 3)
	var main_cards := _expand_entries(main_entries)
	var monster_cards := _expand_entries(monster_entries)
	_main_cards = main_cards
	# The state must exist before pool construction: candidate stamping
	# queries the engine (play-zone restrictions) through it.
	_mcs = MaxCounterState.new(main_cards, monster_cards, _strategy_zone_count)
	_build_pools(main_cards, monster_cards)
	_configs = []
	var monsters: Array = _monster_pool if not _monster_pool.is_empty() else [{}]
	var mzs: Array = [_fixed_monster_zone] if _fixed_monster_zone > 0 else range(1, 9)
	for monster in monsters:
		for mz in mzs:
			_configs.append({"monster": monster, "monster_zone": mz})
	_phase = 0


## One bounded unit of work: seeds one config, or runs one improvement pass
## on one finalist. Returns false when the search is finished and result()
## is ready.
func step() -> bool:
	match _phase:
		0:
			if _configs.is_empty():
				_pick_finalists()
				_phase = 1
				return true
			_seed_config(_configs.pop_front())
			return true
		1:
			if _finalists.is_empty():
				_finalize()
				_phase = 2
				return false
			var finalist: Dictionary = _finalists[0]
			finalist["passes"] += 1
			var improved := _improve(finalist)
			if not improved or finalist["passes"] >= IMPROVE_PASSES:
				_seeded.append(_finalists.pop_front())
			return true
	return false


func result() -> Dictionary:
	return _result


func teardown() -> void:
	if _mcs:
		_mcs.teardown()
	_mcs = null


## Convenience for tests and non-UI callers: run the whole search at once.
func run(monster_entries: Array, main_entries: Array, params: Dictionary = {}) -> Dictionary:
	setup(monster_entries, main_entries, params)
	while step():
		pass
	return result()


# --- Candidate construction ---

func _expand_entries(entries: Array) -> Array[Dictionary]:
	## {card_number, quantity} entries -> per-copy instances with decklist-
	## style ids (CardUtils.base_id-compatible).
	var cards: Array[Dictionary] = []
	for entry in entries:
		var template: Dictionary = CardData.get_card_by_id(entry.get("card_number", ""))
		if template.is_empty():
			continue
		for i in range(entry.get("quantity", 1)):
			var card: Dictionary = template.duplicate(true)
			card["id"] = "%s_0_%d" % [entry["card_number"], i]
			cards.append(card)
	return cards


func _build_pools(main_cards: Array[Dictionary], monster_cards: Array[Dictionary]) -> void:
	_monster_pool = monster_cards.duplicate()
	_monster_pool.sort_custom(_by_id)
	_strategy_pool = []
	var seen_strategies := {}
	var vanillas: Array[Dictionary] = []
	var effectful: Array[Dictionary] = []
	var registry := EffectRegistry.new()
	var queries: EffectQueries = _mcs.effect_handler.queries
	for card in main_cards:
		match card.get("card_type"):
			CardEnums.CardType.BATTLE:
				# Play-zone restrictions (e.g. EBP04-067 "only in zone 8")
				# become a placement constraint _board_valid enforces.
				var required: Array[int] = queries.get_card_required_play_zones(0, card)
				if not required.is_empty():
					card["__zone_lock"] = required
				if _has_cp_trigger(registry, card):
					effectful.append(card)
				else:
					vanillas.append(card)
			CardEnums.CardType.STRATEGY:
				# Up to one copy per strategy slot per id: the strategy
				# zones have no per-name limit, and stacking field-CP
				# strategies (EBP04-082) legitimately field one per slot.
				var base := CardUtils.base_id(card)
				var copies: int = seen_strategies.get(base, 0)
				if copies < _strategy_zone_count:
					seen_strategies[base] = copies + 1
					_strategy_pool.append(card)
	vanillas.sort_custom(_by_cp_desc)
	if vanillas.size() > VANILLA_KEEP:
		vanillas.resize(VANILLA_KEEP)
	_battle_pool = effectful
	_battle_pool.append_array(vanillas)
	_battle_pool.append_array(_token_candidates(main_cards, monster_cards))
	_battle_pool.sort_custom(_by_cp_desc)
	if _battle_pool.size() > POOL_CAP:
		_battle_pool.resize(POOL_CAP)
	_strategy_pool.sort_custom(_by_id)


func _has_cp_trigger(registry: EffectRegistry, card: Dictionary) -> bool:
	for method in CP_TRIGGERS:
		if registry.has_trigger(card, method):
			return true
	return false


func _token_candidates(main_cards: Array[Dictionary], monster_cards: Array[Dictionary]) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	var counter := 0
	for generator_id in TOKEN_SOURCES:
		var source: Dictionary = TOKEN_SOURCES[generator_id]
		var mode: String = source["mode"]
		var in_main := _copies_of(main_cards, generator_id)
		var in_monster := _copies_of(monster_cards, generator_id)
		match mode:
			"replace":
				for copy in in_main:
					# EBP02-077: the mill hits the deck, so a <Godzilla> card
					# OTHER than the fielded copy must exist to trigger it.
					if not _main_has_trait_besides(main_cards, CardEnums.CardTrait.GODZILLA, copy["id"]):
						continue
					var token := _token_instance(source["token"], counter)
					counter += 1
					# The copy and its token can't both be fielded, and each
					# fielded token consumes a never-fielded mill witness
					# (checked in _board_valid).
					token["__pair"] = copy["id"]
					token["__mill_trait"] = CardEnums.CardTrait.GODZILLA
					copy["__pair"] = copy["id"]
					tokens.append(token)
			"extra":
				var from_monster: bool = source.get("source") == "monster"
				var generators: Array[Dictionary] = in_monster if from_monster else in_main
				for copy in generators:
					for _i in range(source["per_copy"]):
						var token := _token_instance(source["token"], counter)
						counter += 1
						if from_monster:
							# A monster generator only ever enters play when
							# the fielded monster's rank reaches it.
							token["__min_monster_rank"] = copy.get("rank", 1)
						tokens.append(token)
			"fill":
				# EBP02-020: 5+ strategies in discard when played — the played
				# copy is in a strategy zone, so it doesn't count itself.
				# Exact witness accounting (fielded strategies were never in
				# the discard) happens per-board in _board_valid via the
				# __fill_gate stamp.
				var strategy_count := 0
				for card in main_cards:
					if card.get("card_type") == CardEnums.CardType.STRATEGY:
						strategy_count += 1
				if in_main.is_empty() or strategy_count - 1 < 5:
					continue
				for _i in range(source["count"]):
					var token := _token_instance(source["token"], counter)
					counter += 1
					token["__fill_gate"] = {"generator": generator_id, "count": 5}
					tokens.append(token)
			"linked":
				# EBP04-067: token locked to zone 3 (idx 2), destroyed unless
				# the generator stays on the board.
				for copy in in_main:
					var token := _token_instance(source["token"], counter)
					counter += 1
					token["__zone_lock"] = source["zone_lock"]
					token["__requires"] = generator_id
					tokens.append(token)
	return tokens


func _token_instance(token_id: String, counter: int) -> Dictionary:
	var card: Dictionary = CardData.get_card_by_id(token_id).duplicate(true)
	card["id"] = "%s_0_%d" % [token_id, counter]
	return card


func _copies_of(cards: Array[Dictionary], base: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for card in cards:
		if CardUtils.base_id(card) == base:
			out.append(card)
	return out


func _main_has_trait_besides(cards: Array[Dictionary], trait_id: int, excluded_id: String) -> bool:
	for card in cards:
		if card["id"] != excluded_id and CardUtils.has_trait(card, trait_id):
			return true
	return false


# --- Seeding ---

func _seed_config(config: Dictionary) -> void:
	var solo := _solo_scores(config)
	var order := _battle_pool.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = solo.get(a["id"], 0)
		var sb: int = solo.get(b["id"], 0)
		return sa > sb if sa != sb else a["id"] < b["id"])

	# Second seed order: effectful (placement-sensitive) cards claim slots —
	# adjacent-to-monster first — before placement-free bodies. Catches the
	# compound trade single-move improvement can't (a big vanilla/token
	# squatting on an adjacent slot an adjacency-conditional card needed):
	# the seeds bracket both allocations and the better one survives.
	var registry := EffectRegistry.new()
	var sensitive_first: Array[Dictionary] = []
	var insensitive: Array[Dictionary] = []
	for card in order:
		if _has_cp_trigger(registry, card):
			sensitive_first.append(card)
		else:
			insensitive.append(card)
	sensitive_first.append_array(insensitive)

	var orders: Array = [order]
	if sensitive_first != order:
		orders.append(sensitive_first)

	# Third seed order: tokens claim slots first. 0-CP enabler tokens (e.g.
	# EBP02-T03 Crystals feeding EBP02-072's flat +20000) never earn a slot
	# on solo score, and the replace pass can't cross that valley one swap at
	# a time — though it CAN trim an over-fielded token seed back down, so
	# fielding every token here is fine.
	var tokens_first: Array[Dictionary] = []
	var non_tokens: Array[Dictionary] = []
	for card in order:
		if CardUtils.has_trait(card, CardEnums.CardTrait.TOKEN):
			tokens_first.append(card)
		else:
			non_tokens.append(card)
	if not tokens_first.is_empty():
		tokens_first.append_array(non_tokens)
		orders.append(tokens_first)

	# Seeds are compared on their FULL board score — unders attached and
	# strategy slots picked — or a seed whose value lives in a tuck
	# (EBP03-064) or a token-fed strategy (EBP02-072) loses a tie or even
	# the comparison itself to a plain-bodies board it actually beats.
	var assignment: Dictionary = {}
	var best_score := -1
	for candidate_order in orders:
		var filled := _greedy_fill(config, candidate_order)
		_attach_unders(filled)
		_pick_strategies(filled)
		_attach_unders(filled)
		var score := _score(filled)
		if score > best_score:
			best_score = score
			assignment = filled

	_seeded.append({
		"assignment": assignment,
		"score": _score(assignment),
		"passes": 0,
	})


func _greedy_fill(config: Dictionary, order: Array) -> Dictionary:
	var assignment := _empty_assignment(config)
	var slots := _slot_order(config["monster_zone"])
	# Two passes so constrained candidates (linked tokens) get a second try
	# once their required generator has been placed.
	for _attempt in range(2):
		for card in order:
			if _on_board(assignment, card["id"]):
				continue
			for slot in slots:
				if not assignment["zones"][slot].is_empty():
					continue
				assignment["zones"][slot] = card
				if _board_valid(assignment):
					break
				assignment["zones"][slot] = {}
	return assignment


func _solo_scores(config: Dictionary) -> Dictionary:
	## Each candidate alone on the board, in the best slot it may occupy —
	## cached per monster_zone (the monster's identity rarely reorders
	## candidates; exact placement is the relocate pass's job).
	var mz: int = config["monster_zone"]
	if _solo_cache.has(mz):
		return _solo_cache[mz]
	var scores := {}
	var slots := _slot_order(mz)
	for card in _battle_pool:
		var assignment := _empty_assignment(config)
		var placed_slot := -1
		for slot in slots:
			assignment["zones"][slot] = card
			if _board_valid(assignment):
				placed_slot = slot
				break
			assignment["zones"][slot] = {}
		if placed_slot < 0:
			# Unplaceable alone (e.g. a linked token without its generator):
			# rank by printed CP so it still sorts sensibly for pass two.
			scores[card["id"]] = card.get("counter_power", 0)
			continue
		# A stack-source top is worth its tucked ceiling, not its printed CP —
		# scored bare, the greedy order benches it behind plain bodies it
		# beats once the under arrives.
		var source: Dictionary = STACK_SOURCES.get(CardUtils.base_id(card), {})
		if not source.is_empty():
			_try_attach(assignment, placed_slot, source)
		scores[card["id"]] = _score(assignment)
	_solo_cache[mz] = scores
	return scores


func _pick_strategies(assignment: Dictionary) -> void:
	## Fill the strategy slots with the best measured deltas (ties broken
	## by id for determinism). Zero-delta strategies are still eligible —
	## they can satisfy "strategy in play" conditions elsewhere.
	var base := _score(assignment)
	var deltas: Array = []
	for card in _strategy_pool:
		assignment["strategies"][0] = card
		deltas.append({"card": card, "delta": _score(assignment) - base})
		assignment["strategies"][0] = {}
	deltas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["delta"] != b["delta"]:
			return a["delta"] > b["delta"]
		return a["card"]["id"] < b["card"]["id"])
	var slot := 0
	for entry in deltas:
		if slot >= _strategy_zone_count or entry["delta"] < 0:
			break
		assignment["strategies"][slot] = entry["card"]
		if _board_valid(assignment):
			slot += 1
		else:
			# e.g. fielding this strategy would consume a mill witness a
			# placed token needs.
			assignment["strategies"][slot] = {}


# --- Improvement ---

func _pick_finalists() -> void:
	_seeded.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"])
	_finalists = _seeded.slice(0, FINALISTS)
	_seeded = _seeded.slice(FINALISTS)


func _improve(finalist: Dictionary) -> bool:
	## One opp-zone sweep + replace + relocate + under-attach + strategy
	## pass. Returns true if the score improved.
	var assignment: Dictionary = finalist["assignment"]
	var best: int = finalist["score"]
	var improved := false

	# Opponent-zone sweep first, so the placement passes below optimize
	# under the adopted zone (only when the user left it unconstrained).
	if _sweep_opp_zone(assignment):
		var swept := _score(assignment)
		if swept > best:
			best = swept
			improved = true

	# Replace: every benched battle candidate into every slot. On a kept
	# improvement the candidate is no longer benched — break to the next
	# candidate, or the same dict would land in a second zone (the
	# duplicate-copy inflation bug). An evicted top takes its under back to
	# the bench (the attach pass may re-tuck later).
	var unders: Dictionary = assignment["unders"]
	for card in _battle_pool:
		if _on_board(assignment, card["id"]):
			continue
		for slot in _slot_order(assignment["monster_zone"]):
			var evicted: Dictionary = assignment["zones"][slot]
			var evicted_under: Dictionary = unders.get(slot, {})
			unders.erase(slot)
			assignment["zones"][slot] = card
			var score := _score(assignment) if _board_valid(assignment) else -1
			if score > best:
				best = score
				improved = true
				break
			assignment["zones"][slot] = evicted
			if not evicted_under.is_empty():
				unders[slot] = evicted_under

	# Relocate: swap every pair of slots (including into empty ones); a
	# stack moves as a unit (its under travels with the top).
	var slots := _slot_order(assignment["monster_zone"])
	for i in range(slots.size()):
		for j in range(i + 1, slots.size()):
			var a: Dictionary = assignment["zones"][slots[i]]
			var b: Dictionary = assignment["zones"][slots[j]]
			if a.is_empty() and b.is_empty():
				continue
			var under_a: Dictionary = unders.get(slots[i], {})
			var under_b: Dictionary = unders.get(slots[j], {})
			assignment["zones"][slots[i]] = b
			assignment["zones"][slots[j]] = a
			_set_under(unders, slots[i], under_b)
			_set_under(unders, slots[j], under_a)
			var score := _score(assignment) if _board_valid(assignment) else -1
			if score > best:
				best = score
				improved = true
			else:
				assignment["zones"][slots[i]] = a
				assignment["zones"][slots[j]] = b
				_set_under(unders, slots[i], under_a)
				_set_under(unders, slots[j], under_b)

	if _attach_unders(assignment):
		best = _score(assignment)
		improved = true

	# Strategy replace: benched strategies into every slot (break on a kept
	# improvement — same dict must not fill two slots).
	for card in _strategy_pool:
		if _on_board(assignment, card["id"]):
			continue
		for i in range(_strategy_zone_count):
			var evicted: Dictionary = assignment["strategies"][i]
			assignment["strategies"][i] = card
			var score := _score(assignment) if _board_valid(assignment) else -1
			if score > best:
				best = score
				improved = true
				break
			assignment["strategies"][i] = evicted

	finalist["score"] = best
	return improved


func _sweep_opp_zone(assignment: Dictionary) -> bool:
	## Best-case opponent monster position: evaluate the board under every
	## opponent zone and adopt the argmax (ties -> lowest zone, for
	## determinism). No-op when the user pinned the opponent zone. Returns
	## true if the zone changed.
	if _fixed_opp_zone > 0:
		return false
	var original: int = assignment["opp_monster_zone"]
	var best_zone: int = original
	var best_score := -1
	for opp_zone in range(1, 9):
		assignment["opp_monster_zone"] = opp_zone
		var score := _score(assignment)
		if score > best_score:
			best_score = score
			best_zone = opp_zone
	assignment["opp_monster_zone"] = best_zone
	return best_zone != original


func _attach_unders(assignment: Dictionary) -> bool:
	## Tuck an eligible card under each placed STACK_SOURCES top that lacks
	## one. Buried cards contribute no CP of their own, so candidates are
	## tried cheapest printed CP first; a FIELDED candidate is detached from
	## its zone/strategy slot (its zone backfilled with the best plain
	## spare) — the engine arbitrates the whole trade, kept only on strict
	## improvement.
	var improved := false
	for i in range(8):
		var top: Dictionary = assignment["zones"][i]
		if top.is_empty() or assignment["unders"].has(i):
			continue
		var source: Dictionary = STACK_SOURCES.get(CardUtils.base_id(top), {})
		if source.is_empty():
			continue
		if _try_attach(assignment, i, source):
			improved = true
	return improved


func _try_attach(assignment: Dictionary, zone_idx: int, source: Dictionary) -> bool:
	var unders: Dictionary = assignment["unders"]
	var base := _score(assignment)
	var top: Dictionary = assignment["zones"][zone_idx]
	var candidates: Array[Dictionary] = []
	for card in _main_cards:
		if _under_eligible(source, card) or _evolves_under(top, card):
			candidates.append(card)
	candidates.sort_custom(_by_cp_asc)
	for card in candidates:
		if card["id"] == assignment["zones"][zone_idx].get("id", "") \
				or _is_under(assignment, card["id"]):
			continue
		var from_zone := -1
		var from_strategy := -1
		for z in range(8):
			if assignment["zones"][z].get("id", "") == card["id"]:
				from_zone = z
				break
		for s in range(assignment["strategies"].size()):
			if assignment["strategies"][s].get("id", "") == card["id"]:
				from_strategy = s
				break
		if from_zone >= 0 and unders.has(from_zone):
			continue  # never orphan another stack's under
		# Tuck first so the backfill lookup can't pick the tucked card.
		unders[zone_idx] = card
		var backfill: Dictionary = {}
		if from_zone >= 0:
			assignment["zones"][from_zone] = {}
			backfill = _best_spare_battle(assignment)
			if not backfill.is_empty():
				assignment["zones"][from_zone] = backfill
		elif from_strategy >= 0:
			assignment["strategies"][from_strategy] = {}
		if _board_valid(assignment) and _score(assignment) > base:
			return true
		unders.erase(zone_idx)
		if from_zone >= 0:
			assignment["zones"][from_zone] = card
		elif from_strategy >= 0:
			assignment["strategies"][from_strategy] = card
	return false


func _is_under(assignment: Dictionary, card_id: String) -> bool:
	var unders: Dictionary = assignment["unders"]
	for slot in unders:
		if unders[slot]["id"] == card_id:
			return true
	return false


func _best_spare_battle(assignment: Dictionary) -> Dictionary:
	## Highest printed-CP unconstrained spare, for backfilling the zone a
	## tucked card vacated (constrained candidates could invalidate the
	## whole trade; the replace pass can upgrade the backfill later).
	for card in _battle_pool:  # sorted by printed CP descending
		if card.has("__zone_lock") or card.has("__requires") \
				or card.has("__mill_trait") or card.has("__pair"):
			continue
		if not _on_board(assignment, card["id"]):
			return card
	return {}


static func _set_under(unders: Dictionary, slot: int, under: Dictionary) -> void:
	if under.is_empty():
		unders.erase(slot)
	else:
		unders[slot] = under


func _finalize() -> void:
	if _seeded.is_empty():
		_result = {}
		return
	_seeded.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"])
	var winner: Dictionary = _seeded[0]
	var assignment: Dictionary = winner["assignment"]
	_sweep_opp_zone(assignment)
	if _fixed_rage < 0:
		# Rage was assumed reachable during the search; keep whichever final
		# rage actually scores higher (guards effects that punish own rage).
		var searched := _score(assignment)
		assignment["rage"] = 0
		if _score(assignment) < searched:
			assignment["rage"] = SEARCH_RAGE
	_mcs.apply(assignment)
	_result = _mcs.breakdown()
	_result["monster"] = assignment["monster"]
	_result["monster_zone"] = assignment["monster_zone"]
	_result["zones"] = assignment["zones"]
	_result["strategies"] = assignment["strategies"]
	_result["rage"] = assignment["rage"]
	_result["opp_monster_zone"] = assignment["opp_monster_zone"]
	_result["unders"] = assignment["unders"]


# --- Board helpers ---

func _empty_assignment(config: Dictionary) -> Dictionary:
	var zones: Array = []
	zones.resize(8)
	zones.fill({})
	var strategies: Array = []
	strategies.resize(_strategy_zone_count)
	strategies.fill({})
	return {
		"monster": config["monster"],
		"monster_zone": config["monster_zone"],
		"zones": zones,
		"strategies": strategies,
		"rage": _fixed_rage if _fixed_rage >= 0 else SEARCH_RAGE,
		"opp_monster_zone": _fixed_opp_zone if _fixed_opp_zone > 0 else 1,
		"unders": {},
	}


func _score(assignment: Dictionary) -> int:
	_mcs.apply(assignment)
	return _mcs.evaluate()


func _slot_order(monster_zone: int) -> Array[int]:
	## Zone indices a battle card may occupy: adjacent to the monster first
	## (where adjacency-conditional cards want to be), then the rest.
	var monster_idx := monster_zone - 1
	var order: Array[int] = []
	for idx in CardEffect.get_adjacent_zones(monster_idx):
		order.append(idx)
	for idx in range(8):
		if idx != monster_idx and idx not in order:
			order.append(idx)
	return order


func _on_board(assignment: Dictionary, card_id: String) -> bool:
	for zone in assignment["zones"]:
		if not zone.is_empty() and zone["id"] == card_id:
			return true
	for sz in assignment["strategies"]:
		if not sz.is_empty() and sz["id"] == card_id:
			return true
	var unders: Dictionary = assignment.get("unders", {})
	for slot in unders:
		if unders[slot]["id"] == card_id:
			return true
	return false


func _board_valid(assignment: Dictionary) -> bool:
	## Structural constraints the engine can't express as CP: token links,
	## generator/token exclusion, mill-witness consumption, monster reach,
	## play-zone restrictions, and instance-id uniqueness (a card copy can
	## only be fielded once — zones, strategy slots and unders combined).
	var monster_idx: int = assignment["monster_zone"] - 1
	var monster_rank: int = assignment["monster"].get("rank", 0)
	var pairs := {}
	var placed_bases := {}
	var fielded_ids := {}
	var mill_needs := {}       # trait_id -> fielded replace-token count
	var consumed_pairs := {}   # generator ids used up by fielded tokens
	var fill_gate := {}        # any fielded fill-token's discard requirement
	for sz in assignment["strategies"]:
		if not sz.is_empty():
			if fielded_ids.has(sz["id"]):
				return false
			fielded_ids[sz["id"]] = true
	for i in range(8):
		var card: Dictionary = assignment["zones"][i]
		if card.is_empty():
			continue
		if i == monster_idx:
			return false
		if fielded_ids.has(card["id"]):
			return false
		fielded_ids[card["id"]] = true
		placed_bases[CardUtils.base_id(card)] = true
		if card.has("__pair"):
			if pairs.has(card["__pair"]):
				return false
			pairs[card["__pair"]] = true
		if card.has("__zone_lock") and i not in (card["__zone_lock"] as Array):
			return false
		if card.has("__min_monster_rank") and monster_rank < int(card["__min_monster_rank"]):
			return false
		if card.has("__mill_trait"):
			var trait_id: int = card["__mill_trait"]
			mill_needs[trait_id] = mill_needs.get(trait_id, 0) + 1
			consumed_pairs[card["__pair"]] = true
		if card.has("__fill_gate") and fill_gate.is_empty():
			fill_gate = card["__fill_gate"]
	for i in range(8):
		var card: Dictionary = assignment["zones"][i]
		if not card.is_empty() and card.has("__requires") \
				and not placed_bases.has(card["__requires"]):
			return false
	if not _unders_valid(assignment, fielded_ids):
		return false
	# Every fielded replace-token consumed a distinct mill witness: a card
	# with the trait that was never fielded (stayed in the deck to be milled).
	for trait_id in mill_needs:
		var eligible := 0
		for card in _main_cards:
			if fielded_ids.has(card["id"]) or consumed_pairs.has(card["id"]):
				continue
			if CardUtils.has_trait(card, trait_id):
				eligible += 1
		if eligible < mill_needs[trait_id]:
			return false
	# Fill tokens (EBP02-020) needed N strategies IN THE DISCARD when the
	# generator was played — fielded strategies were played from hand and
	# can't double as those witnesses. The generator copy itself counts only
	# when fielded (it was played, not discarded).
	if not fill_gate.is_empty():
		var generator_base: String = fill_gate["generator"]
		var witnesses := 0
		var generator_ok := false
		for card in _main_cards:
			if card.get("card_type") != CardEnums.CardType.STRATEGY:
				continue
			var is_generator := CardUtils.base_id(card) == generator_base
			if fielded_ids.has(card["id"]):
				if is_generator:
					generator_ok = true
				continue
			if is_generator and not generator_ok:
				# One unfielded copy is reserved as the played generator.
				generator_ok = true
				continue
			witnesses += 1
		if not generator_ok or witnesses < int(fill_gate["count"]):
			return false
	return true


func _unders_valid(assignment: Dictionary, fielded_ids: Dictionary) -> bool:
	## Under-cards must sit beneath a STACK_SOURCES top, pass its filter, be
	## unique instances, and strategy-sourced tucks must leave room in the
	## strategy slots they came from. Mutates fielded_ids (shared
	## uniqueness set — also makes unders count as fielded for the caller's
	## mill-witness accounting).
	var unders: Dictionary = assignment.get("unders", {})
	if unders.is_empty():
		return true
	var strategy_unders := 0
	for zone_idx in unders:
		var under: Dictionary = unders[zone_idx]
		var top: Dictionary = assignment["zones"][zone_idx] if zone_idx < 8 else {}
		if top.is_empty():
			return false
		var source: Dictionary = STACK_SOURCES.get(CardUtils.base_id(top), {})
		if source.is_empty():
			return false
		# An evolution-qualified under never came from a strategy zone, so it
		# skips the strategy-slot accounting below.
		var via_evolution := _evolves_under(top, under)
		if not via_evolution and not _under_eligible(source, under):
			return false
		if fielded_ids.has(under["id"]):
			return false
		fielded_ids[under["id"]] = true
		if not via_evolution and source["source"] == "strategy":
			strategy_unders += 1
	if strategy_unders > 0:
		var filled := 0
		for sz in assignment["strategies"]:
			if not sz.is_empty():
				filled += 1
		if strategy_unders + filled > _strategy_zone_count:
			return false
	return true


func _evolves_under(top: Dictionary, under: Dictionary) -> bool:
	## Evolution as an under source: the under was fielded first, then the top
	## was played from the deck onto it by perform_evolution — legal when the
	## under's evolution_rank/evolution_trait cover the top's rank/traits.
	if not CardUtils.is_battle(top) or not CardUtils.is_battle(under):
		return false
	if not under.has("evolution_rank") or not under.has("evolution_trait"):
		return false
	return top.get("rank", 0) <= int(under["evolution_rank"]) \
			and CardUtils.has_trait(top, int(under["evolution_trait"]))


func _under_eligible(source: Dictionary, card: Dictionary) -> bool:
	match source["filter"]:
		"battle":
			return CardUtils.is_battle(card)
		"traits_all":
			for trait_id in source["traits"]:
				if not CardUtils.has_trait(card, trait_id):
					return false
			return true
		"trait":
			return CardUtils.is_battle(card) and CardUtils.has_trait(card, source["trait"])
		"invasion_icon":
			return card.get("card_type") == CardEnums.CardType.STRATEGY \
					and card.get("invasion_icon", 0) == source["value"]
	return false


static func _by_cp_desc(a: Dictionary, b: Dictionary) -> bool:
	var ca: int = a.get("counter_power", 0)
	var cb: int = b.get("counter_power", 0)
	return ca > cb if ca != cb else a["id"] < b["id"]


static func _by_cp_asc(a: Dictionary, b: Dictionary) -> bool:
	var ca: int = a.get("counter_power", 0)
	var cb: int = b.get("counter_power", 0)
	return ca < cb if ca != cb else a["id"] < b["id"]


static func _by_id(a: Dictionary, b: Dictionary) -> bool:
	return a["id"] < b["id"]
