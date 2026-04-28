class_name PlayerState
extends RefCounted

signal hand_changed()
signal zones_changed()
signal monster_changed()
signal rage_changed(new_rage: int)
signal strategy_zones_changed()
signal deck_changed()
signal discard_changed()
signal discard_reshuffled()

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
# Transient claim bucket: holds RAGE-MARKER instances during a rage-decrease
# standby pass so claiming effects (e.g. EBP04-089) can pop them. Populated by
# the rage-decrease site, drained by listeners, cleared at the end of the
# trigger window. Never persists across events.
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


func push_zone_card(i: int, card: Dictionary) -> void:
	zones[i].push_front(card)


func clear_zone(i: int) -> Array:
	var stack: Array = zones[i].duplicate()
	zones[i] = []
	return stack


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


func get_zone_top_indices_matching(filter: Callable) -> Array[int]:
	## Return occupied zone indices whose top card matches the filter predicate.
	## Filter signature: func(card: Dictionary) -> bool.
	var indices: Array[int] = []
	for i in range(8):
		var top: Dictionary = get_zone_top_card(i)
		if not top.is_empty() and filter.call(top):
			indices.append(i)
	return indices


func get_zone_top_cards_matching(filter: Callable) -> Array[Dictionary]:
	## Return the top cards of occupied zones that match the filter predicate.
	var cards: Array[Dictionary] = []
	for i in range(8):
		var top: Dictionary = get_zone_top_card(i)
		if not top.is_empty() and filter.call(top):
			cards.append(top)
	return cards


func count_zones_matching(filter: Callable) -> int:
	## Count occupied zones whose top card matches the filter predicate.
	var n: int = 0
	for i in range(8):
		var top: Dictionary = get_zone_top_card(i)
		if not top.is_empty() and filter.call(top):
			n += 1
	return n


func has_zone_matching(filter: Callable) -> bool:
	## True if any occupied zone's top card matches the filter predicate.
	for i in range(8):
		var top: Dictionary = get_zone_top_card(i)
		if not top.is_empty() and filter.call(top):
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
	for i in range(2):
		if strategy_zones[i].is_empty():
			return i
	return -1


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
	## Count how many zones have a token with the given ID as top card.
	var count: int = 0
	for i in range(8):
		var top := get_zone_top_card(i)
		if not top.is_empty() and is_token(top) and top.get("id", "") == token_id:
			count += 1
	return count


func _reshuffle_discard() -> void:
	if discard_pile.is_empty():
		return
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
	discard_reshuffled.emit()
