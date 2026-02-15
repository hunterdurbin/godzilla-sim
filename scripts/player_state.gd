class_name PlayerState
extends RefCounted

signal hand_changed()
signal zones_changed()
signal monster_changed()
signal rage_changed(new_rage: int)
signal strategy_zones_changed()
signal deck_changed()
signal discard_changed()

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
var has_invaded_this_turn: bool = false
var has_played_monster_this_turn: bool = false
var strategy_zone_turn_placed: Array[int] = [0, 0]  # Turn number when each was placed
var monster_stack: Array[Dictionary] = []  # Monsters stacked under current_monster (index 0 = directly below top)
var burst_monster: Dictionary = {}  # The Burst-played monster (empty if none active)
var pre_burst_monster: Dictionary = {}  # Monster that was active before Burst play
var last_invasion_card: Dictionary = {}  # Card discarded for the most recent invade action
var invasion_zones_crossed: int = 0  # Zones actually crossed during invasion this turn
var cards_destroyed_this_turn: Array[Dictionary] = []  # Cards destroyed on this player's board this turn


func _init(id: int = 0) -> void:
	player_id = id
	zones.resize(8)
	for i in range(8):
		zones[i] = []
	strategy_zones.resize(2)
	strategy_zones[0] = {}
	strategy_zones[1] = {}


# --- Zone stack helpers ---

func is_zone_empty(i: int) -> bool:
	return zones[i].is_empty() and i != monster_zone - 1


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


func get_occupied_zone_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in range(8):
		if not is_zone_empty(i):
			indices.append(i)
	return indices


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
	# Safety: filter out any tokens that leaked into discard
	var non_tokens: Array[Dictionary] = []
	for card in discard_pile:
		if not is_token(card):
			non_tokens.append(card)
	main_deck.append_array(non_tokens)
	discard_pile.clear()
	main_deck.shuffle()
	deck_changed.emit()
	discard_changed.emit()
