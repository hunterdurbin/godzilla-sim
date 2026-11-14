class_name PlayerState
extends RefCounted

# Change signals: emitted only by this class, by the mutator that made the
# change, immediately (no batching). Subscribed by GameBoard / HeadlessBoard
# (state sync) and TurnManager (hand_changed).
signal hand_changed()
signal zones_changed()
## The monster card, the cards under it, or the monster deck changed.
signal monster_changed()
signal rage_changed(new_rage: int)
signal strategy_zones_changed()
signal deck_changed()
signal discard_changed()
signal discard_reshuffled(moved_cards: Array)

var player_id: int = 0
var monster_deck: Array[Dictionary] = []  # Rank I-IV, ordered
var current_monster: Dictionary = {}
var monster_zone: int = 1  # Current zone number (1-8) of invading monster
var rage: int = 0
var main_deck: Array[Dictionary] = []
var hand: Array[Dictionary] = []
var discard_pile: Array[Dictionary] = []
var zones: Array = []  # 8 entries, each an Array of Dictionaries (card stack, index 0 = top)
var strategy_zones: Array = []  # Up to 2 entries, each {} or a strategy card dict
var strategy_zone_stacks: Array = []  # Parallel to strategy_zones: cards stacked under each strategy (e.g. EBP04-089)
var has_invaded_this_turn: bool = false
var has_played_monster_this_turn: bool = false
var strategy_zone_turn_placed: Array[int] = [0, 0]  # Turn number when each was placed
var monster_stack: Array[Dictionary] = []  # Monsters stacked under current_monster (index 0 = directly below top)
var burst_monster: Dictionary = {}  # The Burst-played monster (empty if none active)
var pre_burst_monster: Dictionary = {}  # Monster that was active before Burst play
var last_invasion_card: Dictionary = {}  # Card discarded for the most recent invade action
var invasion_zones_crossed: int = 0  # Zones actually crossed during invasion this turn
var cards_destroyed_this_turn: Array[Dictionary] = []  # Cards destroyed on this player's board this turn
# Transient claim bucket: holds RAGE-MARKER instances from a rage decrease
# until the check timing that resolves its triggers, so claiming effects
# (e.g. EBP04-089) can pop them. Populated by the rage-decrease site, drained
# by listeners; CheckTiming.resolve clears the leftovers once its pass ends.
var pending_rage_markers: Array = []


func _init(id: int = 0) -> void:
	player_id = id
	zones.resize(8)
	for i in range(8):
		zones[i] = []
	strategy_zones.resize(2)
	strategy_zones[0] = {}
	strategy_zones[1] = {}
	strategy_zone_stacks.resize(2)
	strategy_zone_stacks[0] = []
	strategy_zone_stacks[1] = []


# --- Zone stack helpers ---

func is_zone_empty(i: int) -> bool:
	return zones[i].is_empty() and i != monster_zone - 1


func zone_has_battle_card(i: int) -> bool:
	return not zones[i].is_empty()


func zone_has_cards(i: int) -> bool:
	return not zones[i].is_empty()


func get_zone_top_card(i: int) -> Dictionary:
	if zones[i].is_empty():
		return {}
	return zones[i][0]


func get_zone_stack(i: int) -> Array:
	return zones[i]


# --- Mutators ---
# Engine code (scripts/core/, scripts/effects/) changes the player's areas only
# through these methods (and draw_cards / mill_cards / _reshuffle_discard).
# Each call emits its *_changed signal before returning; a bulk mutator
# (add_cards_to_*, put_cards_on_deck_*) emits once for its batch. Callers never
# emit by hand and never hold a signal back across calls
# (scripts/tools/check_card_mutations.py).

func push_zone_card(i: int, card: Dictionary) -> void:
	## Put a card on top of zone i's stack.
	zones[i].push_front(card)
	zones_changed.emit()


func add_card_under_zone(i: int, card: Dictionary) -> void:
	## Put a card at the bottom of zone i's stack.
	zones[i].append(card)
	zones_changed.emit()


func clear_zone(i: int) -> Array:
	## Empty zone i and return its stack (top first).
	var stack: Array = zones[i].duplicate()
	zones[i] = []
	zones_changed.emit()
	return stack


func remove_cards_under_top(i: int) -> Array:
	## Strip the cards under zone i's top card and return them (top first);
	## the top card stays. Emits nothing when there are none.
	if zones[i].size() <= 1:
		return []
	var under: Array = zones[i].slice(1)
	zones[i] = [zones[i][0]]
	zones_changed.emit()
	return under


func swap_zone_stacks(a: int, b: int) -> void:
	## Exchange the whole stacks of zones a and b.
	var stack_a: Array = zones[a]
	zones[a] = zones[b]
	zones[b] = stack_a
	zones_changed.emit()


func move_zone_stack(from_zone: int, to_zone: int) -> void:
	## Move zone from_zone's whole stack onto to_zone, replacing what is there
	## (the caller overloads the destination first).
	var stack: Array = zones[from_zone]
	zones[from_zone] = []
	zones[to_zone] = stack
	zones_changed.emit()


func add_to_hand(card: Dictionary) -> void:
	## Append a card to the end of the hand.
	hand.append(card)
	hand_changed.emit()


func add_cards_to_hand(cards: Array) -> void:
	if cards.is_empty():
		return
	hand.append_array(cards)
	hand_changed.emit()


func insert_into_hand(index: int, card: Dictionary) -> void:
	## Put a card back at a hand position (a cancelled play / cost).
	hand.insert(index, card)
	hand_changed.emit()


func remove_hand_card_at(index: int) -> Dictionary:
	## Take the card at a hand index out of the hand and return it.
	var card: Dictionary = hand.pop_at(index)
	hand_changed.emit()
	return card


func remove_from_hand(card: Dictionary) -> bool:
	## Remove the first hand card equal to `card`; false (no signal) if absent.
	var i: int = hand.find(card)
	if i < 0:
		return false
	hand.remove_at(i)
	hand_changed.emit()
	return true


func add_to_discard(card: Dictionary) -> void:
	discard_pile.append(card)
	discard_changed.emit()


func add_cards_to_discard(cards: Array) -> void:
	if cards.is_empty():
		return
	discard_pile.append_array(cards)
	discard_changed.emit()


func remove_discard_card_at(index: int) -> Dictionary:
	var card: Dictionary = discard_pile.pop_at(index)
	discard_changed.emit()
	return card


func remove_from_discard(card: Dictionary) -> bool:
	## Remove the first discard card equal to `card`; false (no signal) if absent.
	var i: int = discard_pile.find(card)
	if i < 0:
		return false
	discard_pile.remove_at(i)
	discard_changed.emit()
	return true


func set_main_deck(cards: Array) -> void:
	## Replace the main deck (match setup).
	main_deck.assign(cards)
	deck_changed.emit()


func take_deck_top_cards(count: int) -> Array[Dictionary]:
	## Take up to `count` cards off the top of the deck, top first (fewer if
	## it runs out; no reshuffle). Emits nothing when nothing was taken.
	var taken: Array[Dictionary] = []
	while taken.size() < count and not main_deck.is_empty():
		taken.append(main_deck.pop_front())
	if not taken.is_empty():
		deck_changed.emit()
	return taken


func remove_deck_card_at(index: int) -> Dictionary:
	var card: Dictionary = main_deck.pop_at(index)
	deck_changed.emit()
	return card


func put_on_deck_top(card: Dictionary) -> void:
	main_deck.push_front(card)
	deck_changed.emit()


func put_cards_on_deck_top(cards: Array) -> void:
	## Put cards on top of the deck so cards[0] ends up on top.
	if cards.is_empty():
		return
	for i in range(cards.size() - 1, -1, -1):
		main_deck.push_front(cards[i])
	deck_changed.emit()


func put_on_deck_bottom(card: Dictionary) -> void:
	main_deck.append(card)
	deck_changed.emit()


func put_cards_on_deck_bottom(cards: Array) -> void:
	if cards.is_empty():
		return
	main_deck.append_array(cards)
	deck_changed.emit()


func shuffle_deck() -> void:
	## Shuffle with the global RNG (seeded sims and replays rely on it).
	main_deck.shuffle()
	deck_changed.emit()


func set_monster_deck(cards: Array) -> void:
	## Replace the monster deck (match setup).
	monster_deck.assign(cards)
	monster_changed.emit()


func remove_from_monster_deck(card: Dictionary) -> bool:
	var i: int = monster_deck.find(card)
	if i < 0:
		return false
	monster_deck.remove_at(i)
	monster_changed.emit()
	return true


func set_current_monster(card: Dictionary) -> void:
	current_monster = card
	monster_changed.emit()


func push_under_monster(card: Dictionary) -> void:
	## Put a card directly under the monster card (monster_stack front).
	monster_stack.push_front(card)
	monster_changed.emit()


func add_cards_under_monster(cards: Array) -> void:
	## Put cards at the bottom of the monster stack.
	if cards.is_empty():
		return
	monster_stack.append_array(cards)
	monster_changed.emit()


func pop_under_monster() -> Dictionary:
	## Take the card directly under the monster card ({} when none).
	if monster_stack.is_empty():
		return {}
	var card: Dictionary = monster_stack.pop_front()
	monster_changed.emit()
	return card


func set_monster_zone(zone: int) -> void:
	## Move the monster card to a zone number (1-8, 9 = past zone 8). Only
	## MonsterMover calls this: it runs Crush and the advance / invasion
	## entries per step (scripts/tools/check_monster_zone_writers.py).
	monster_zone = zone
	monster_changed.emit()


func set_rage(value: int) -> void:
	## Set rage; emits rage_changed(value). Rage triggers are the caller's
	## (EffectHandler.gain_rage / reduce_rage dispatch them).
	rage = value
	rage_changed.emit(rage)


func place_strategy(i: int, card: Dictionary, turn_number: int) -> void:
	## Occupy strategy zone i, stamping the turn it was placed (7.2.3).
	strategy_zones[i] = card
	strategy_zone_turn_placed[i] = turn_number
	strategy_zones_changed.emit()


func add_card_under_strategy(i: int, card: Dictionary) -> void:
	strategy_zone_stacks[i].append(card)
	strategy_zones_changed.emit()


func clear_strategy_zone(i: int) -> Dictionary:
	## Empty strategy zone i and drop the cards stacked under it (RAGE
	## markers never enter the discard pile). Returns the strategy card.
	var card: Dictionary = strategy_zones[i]
	strategy_zones[i] = {}
	if i < strategy_zone_stacks.size():
		strategy_zone_stacks[i] = []
	strategy_zones_changed.emit()
	return card


func get_threat_level() -> int:
	return current_monster.get("threat_level", 0) + (rage * 5000)


# --- Effect predicate helpers (rule-text shorthands) ---

func is_awakening(threshold: int) -> bool:
	return monster_zone >= threshold


func has_monster_stack(min_count: int) -> bool:
	return monster_stack.size() >= min_count


func has_rage() -> bool:
	return rage > 0


func push_pending_rage_markers(count: int) -> void:
	## Append `count` RAGE-MARKER instances to the transient claim bucket.
	## Called by rage-decrease sites before firing trigger_rage_changed so that
	## claiming effects can pop_back() markers as a true resource.
	if count <= 0:
		return
	var template: Dictionary = CardData.get_card_by_id("RAGE-MARKER")
	if template.is_empty():
		return
	for _i in range(count):
		pending_rage_markers.append(template.duplicate())


func clear_pending_rage_markers() -> void:
	## Drop the markers no claiming effect took (called by the check timing
	## once the triggers of the decrease have resolved).
	pending_rage_markers.clear()


func get_total_counter_power() -> int:
	var total: int = 0
	for i in range(8):
		var top_card := get_zone_top_card(i)
		if not top_card.is_empty():
			total += top_card.get("counter_power", 0)
	return total


func draw_cards(count: int) -> Array[Dictionary]:
	var drawn: Array[Dictionary] = []
	for i in range(count):
		if main_deck.is_empty():
			_reshuffle_discard()
			if main_deck.is_empty():
				break
		drawn.append(main_deck.pop_front())
	hand.append_array(drawn)
	if drawn.size() > 0:
		hand_changed.emit()
		deck_changed.emit()
	return drawn


func draw_up_to(target_count: int) -> Array[Dictionary]:
	var needed: int = target_count - hand.size()
	if needed <= 0:
		return []
	return draw_cards(needed)


func has_empty_zone() -> bool:
	for i in range(8):
		if is_zone_empty(i):
			return true
	return false


func get_empty_zone_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in range(8):
		if is_zone_empty(i):
			indices.append(i)
	return indices


func get_battle_card_zone_indices() -> Array[int]:
	## Zones holding a battle card. The monster zone is included only if a
	## battle card is also stacked there. Use this for "battle cards in zones"
	## semantics; use `get_empty_zone_indices` for placement.
	var indices: Array[int] = []
	for i in range(8):
		if zone_has_battle_card(i):
			indices.append(i)
	return indices


# --- Card-scan helpers ---
# Rules "zones" = the 8 battle zones (incl. the monster card standing in one)
# plus the 2 strategy zones. The *_battle_card* helpers scan ONLY the top
# battle card of each of the 8 battle zones — use them for "battle card(s) in
# your zones" text. Use has_card_in_zones_matching for bare "a card ... in
# your zones" text, which also covers the monster and strategy cards.
# Filter signature: func(card: Dictionary) -> bool.

func get_battle_card_zone_indices_matching(filter: Callable) -> Array[int]:
	## Indices (0-7) of battle zones whose top battle card matches the filter.
	var indices: Array[int] = []
	for i in range(8):
		var top: Dictionary = get_zone_top_card(i)
		if not top.is_empty() and filter.call(top):
			indices.append(i)
	return indices


func get_battle_cards_matching(filter: Callable) -> Array[Dictionary]:
	## Top battle cards of the 8 battle zones that match the filter.
	var cards: Array[Dictionary] = []
	for i in range(8):
		var top: Dictionary = get_zone_top_card(i)
		if not top.is_empty() and filter.call(top):
			cards.append(top)
	return cards


func count_battle_cards_matching(filter: Callable) -> int:
	## Count battle zones whose top battle card matches the filter.
	var n: int = 0
	for i in range(8):
		var top: Dictionary = get_zone_top_card(i)
		if not top.is_empty() and filter.call(top):
			n += 1
	return n


func has_battle_card_matching(filter: Callable) -> bool:
	## True if any battle zone's top battle card matches the filter.
	for i in range(8):
		var top: Dictionary = get_zone_top_card(i)
		if not top.is_empty() and filter.call(top):
			return true
	return false


func has_card_in_zones_matching(filter: Callable) -> bool:
	## True if any card in your zones matches the filter: a top battle card,
	## the monster card, or a strategy card. Cards stacked underneath (monster
	## stack, evolution stacks, strategy_zone_stacks) are not scanned.
	if has_battle_card_matching(filter):
		return true
	if not current_monster.is_empty() and filter.call(current_monster):
		return true
	for sz in strategy_zones:
		if not sz.is_empty() and filter.call(sz):
			return true
	return false


func mill_cards(count: int) -> Array[Dictionary]:
	## Send top N cards from deck to discard pile. Returns the milled cards.
	var milled: Array[Dictionary] = []
	for _i in range(count):
		if main_deck.is_empty():
			break
		var card: Dictionary = main_deck.pop_front()
		discard_pile.append(card)
		milled.append(card)
	if not milled.is_empty():
		deck_changed.emit()
		discard_changed.emit()
	return milled


func has_empty_strategy_zone() -> bool:
	for sz in strategy_zones:
		if sz.is_empty():
			return true
	return false


func get_first_empty_strategy_zone_index() -> int:
	for i in range(strategy_zones.size()):
		if strategy_zones[i].is_empty():
			return i
	return -1


func ensure_strategy_zone_count(count: int) -> bool:
	## Grow the strategy zones to `count` (never shrinks), keeping the parallel
	## strategy_zone_stacks / strategy_zone_turn_placed arrays in step. New
	## zones start empty. Emits strategy_zones_changed and returns true when
	## zones were added.
	if strategy_zones.size() >= count:
		return false
	while strategy_zones.size() < count:
		strategy_zones.append({})
	while strategy_zone_stacks.size() < count:
		strategy_zone_stacks.append([])
	while strategy_zone_turn_placed.size() < count:
		strategy_zone_turn_placed.append(0)
	strategy_zones_changed.emit()
	return true


func count_strategies_in_play() -> int:
	var n: int = 0
	for sz in strategy_zones:
		if not sz.is_empty():
			n += 1
	return n


func has_any_strategy_in_play() -> bool:
	for sz in strategy_zones:
		if not sz.is_empty():
			return true
	return false


func get_monster_rank() -> int:
	return current_monster.get("rank", 1)


static func is_token(card: Dictionary) -> bool:
	## Returns true if the card is a token (has the TOKEN trait).
	var traits: Array = card.get("traits", [])
	return CardEnums.CardTrait.TOKEN in traits


func count_zone_tokens_by_id(token_id: String) -> int:
	## Count how many zones have a token with the given base ID as top card.
	## Compared via base_id: engine-created tokens carry the plain template id,
	## but deck-analysis boards stamp per-copy instance ids ("EBP02-T03_0_1").
	var count: int = 0
	for i in range(8):
		var top := get_zone_top_card(i)
		if not top.is_empty() and is_token(top) and CardUtils.base_id(top) == token_id:
			count += 1
	return count


func _reshuffle_discard() -> Array[Dictionary]:
	## Move the discard pile into the deck and shuffle. Returns the cards that were
	## moved (token/marker-filtered), so listeners can log/snapshot them. Returns an
	## empty array when there was nothing to reshuffle.
	if discard_pile.is_empty():
		return []
	# Safety: filter out tokens and engine-internal markers (e.g. RAGE-MARKER)
	# that leaked into the discard pile — they must never reach the deck.
	var deckable: Array[Dictionary] = []
	for card in discard_pile:
		if is_token(card):
			continue
		if card.get("card_type") == CardEnums.CardType.RAGE:
			continue
		deckable.append(card)
	main_deck.append_array(deckable)
	discard_pile.clear()
	main_deck.shuffle()
	deck_changed.emit()
	discard_changed.emit()
	discard_reshuffled.emit(deckable)
	return deckable
