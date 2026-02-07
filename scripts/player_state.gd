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
var zones: Array = []  # 8 entries, each {} (empty) or a battle card dict
var strategy_zones: Array = []  # Up to 2 entries, each {} or a strategy card dict
var has_invaded_this_turn: bool = false
var has_played_monster_this_turn: bool = false
var strategy_zone_turn_placed: Array[int] = [0, 0]  # Turn number when each was placed
var burst_monster: Dictionary = {}  # The Burst-played monster (empty if none active)
var pre_burst_monster: Dictionary = {}  # Monster that was active before Burst play


func _init(id: int = 0) -> void:
	player_id = id
	zones.resize(8)
	for i in range(8):
		zones[i] = {}
	strategy_zones.resize(2)
	strategy_zones[0] = {}
	strategy_zones[1] = {}


func get_threat_level() -> int:
	return current_monster.get("threat_level", 0) + (rage * 5000)


func get_total_counter_power() -> int:
	var total: int = 0
	for zone_card in zones:
		if not zone_card.is_empty():
			total += zone_card.get("counter_power", 0)
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
	for zone_card in zones:
		if zone_card.is_empty():
			return true
	return false


func get_empty_zone_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in range(8):
		if zones[i].is_empty():
			indices.append(i)
	return indices


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


func _reshuffle_discard() -> void:
	if discard_pile.is_empty():
		return
	main_deck.append_array(discard_pile)
	discard_pile.clear()
	main_deck.shuffle()
	deck_changed.emit()
	discard_changed.emit()
