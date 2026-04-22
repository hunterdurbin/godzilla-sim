class_name RulesEngine
extends RefCounted

## Pure validation logic for the Godzilla TCG. No side effects.

var effect_handler: EffectHandler


func get_valid_actions(state: GameState) -> Array:
	var actions: Array = [CardEnums.ActionType.PASS]
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()

	# Can play battle card?
	if _can_play_any_battle_card(player, opponent):
		actions.append(CardEnums.ActionType.PLAY_BATTLE)

	# Can activate strategy?
	if _can_play_any_strategy_card(player):
		actions.append(CardEnums.ActionType.PLAY_STRATEGY)

	# Can gain rage? (has a monster card in hand to discard)
	if _has_monster_in_hand(player):
		actions.append(CardEnums.ActionType.GAIN_RAGE)

	# Can play monster? (same rank + matching trait as current monster)
	if _can_play_any_monster(player):
		actions.append(CardEnums.ActionType.PLAY_MONSTER)

	# Can invade? (has any card to discard with invasion_icon > 0, hasn't invaded this turn)
	if _can_invade(player, opponent):
		# Check if opponent's cards block invasion (e.g. EBP02-068 column lock)
		if not effect_handler or not effect_handler.is_invasion_blocked(opponent.player_id):
			actions.append(CardEnums.ActionType.INVADE)

	return actions


func get_playable_battle_cards(player: PlayerState, opponent: PlayerState) -> Array[int]:
	## Returns hand indices of battle cards that can be played
	var indices: Array[int] = []
	var valid_zones := get_valid_zones_for_battle_card(player, opponent)
	if valid_zones.is_empty():
		return indices
	for i in range(player.hand.size()):
		var card: Dictionary = player.hand[i]
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			# Check play restrictions (e.g. EBP01-073 discard pile requirement)
			if effect_handler and not effect_handler.can_card_be_played(player.player_id, card):
				continue
			var base_rank: int = card.get("rank", 99)
			if effect_handler:
				base_rank += effect_handler.get_play_rank_modifier(player.player_id, card)
			if base_rank <= opponent.monster_zone:
				indices.append(i)
			elif effect_handler:
				# Check if any zone provides enough rank reduction
				for zi in valid_zones:
					var zone_mod: int = effect_handler.get_zone_play_rank_modifier(player.player_id, card, zi)
					if zone_mod != 0 and base_rank + zone_mod <= opponent.monster_zone:
						indices.append(i)
						break
	return indices


func get_valid_zones_for_battle_card(player: PlayerState, opponent: PlayerState) -> Array[int]:
	## Returns zone indices (0-7) where a battle card can be placed
	## Zone must not be occupied by own invading monster (can overload occupied zones per rule 11.5)
	## Also excludes zones blocked by opponent's card effects (e.g. EBP02-055)
	var valid: Array[int] = []
	var blocked: Array[int] = []
	if effect_handler:
		blocked = effect_handler.get_opponent_blocked_zones(opponent.player_id)
	for i in range(8):
		if (player.monster_zone - 1) != i and i not in blocked:
			valid.append(i)
	return valid


func get_valid_zones_for_card(card: Dictionary, player: PlayerState, opponent: PlayerState) -> Array[int]:
	## Returns zone indices where a specific battle card can be played (rank-aware).
	var valid: Array[int] = []
	for zi in get_valid_zones_for_battle_card(player, opponent):
		if can_play_battle_card_at_zone(card, zi, player, opponent):
			valid.append(zi)
	return valid


func can_play_battle_card_at_zone(card: Dictionary, zone_index: int, player: PlayerState, opponent: PlayerState) -> bool:
	if card.get("card_type") != CardEnums.CardType.BATTLE:
		return false
	var effective_rank: int = card.get("rank", 99)
	if effect_handler:
		effective_rank += effect_handler.get_play_rank_modifier(player.player_id, card)
		effective_rank += effect_handler.get_zone_play_rank_modifier(player.player_id, card, zone_index)
	if effective_rank > opponent.monster_zone:
		return false
	if zone_index < 0 or zone_index >= 8:
		return false
	if (player.monster_zone - 1) == zone_index:
		return false
	if effect_handler:
		var blocked: Array[int] = effect_handler.get_opponent_blocked_zones(opponent.player_id)
		if zone_index in blocked:
			return false
		var required: Array[int] = effect_handler.get_card_required_play_zones(player.player_id, card)
		if not required.is_empty() and zone_index not in required:
			return false
	return true


func get_playable_strategy_cards(player: PlayerState) -> Array[int]:
	## Returns hand indices of strategy cards that can be activated
	var indices: Array[int] = []
	if not player.has_empty_strategy_zone():
		return indices
	# Check if opponent blocks strategy plays (e.g. EBP02-070)
	if effect_handler and effect_handler.are_opponent_strategy_plays_blocked(player.player_id):
		return indices
	for i in range(player.hand.size()):
		var card: Dictionary = player.hand[i]
		if card.get("card_type") == CardEnums.CardType.STRATEGY:
			var effective_rank: int = card.get("rank", 99)
			if effect_handler:
				effective_rank += effect_handler.get_play_rank_modifier(player.player_id, card)
				effective_rank += effect_handler.get_strategy_hand_rank_modifier(player.player_id, card)
			if effective_rank <= player.monster_zone:
				indices.append(i)
	return indices


func get_discardable_cards_for_invade(player: PlayerState, opponent: PlayerState) -> Array[int]:
	## Returns hand indices of cards that can be discarded for invasion
	var indices: Array[int] = []
	if player.has_invaded_this_turn:
		return indices
	if effect_handler and effect_handler.is_own_invasion_blocked(player.player_id):
		return indices
	if effect_handler and effect_handler.is_invasion_blocked(opponent.player_id):
		return indices
	# Can't invade if already at zone 8 and blocked by opponent's battle card
	if player.monster_zone >= 8 and opponent.zone_has_battle_card(7):
		return indices
	for i in range(player.hand.size()):
		if player.hand[i].get("invasion_icon", 0) > 0:
			indices.append(i)
	return indices


func get_monster_cards_for_rage(player: PlayerState) -> Array[int]:
	## Returns hand indices of monster cards that can be discarded for rage
	var indices: Array[int] = []
	for i in range(player.hand.size()):
		if player.hand[i].get("card_type") == CardEnums.CardType.MONSTER:
			indices.append(i)
	return indices


func get_playable_monsters(player: PlayerState) -> Array[int]:
	## Returns hand indices of monster cards that can be played onto the invading monster.
	## Includes Burst monsters: a card with Burst N can be played when current monster is rank N.
	## Limited to 1 monster play per turn (including burst).
	var indices: Array[int] = []
	var cur_rank: int = player.current_monster.get("rank", 0)
	var cur_traits: Array = player.current_monster.get("traits", [])

	if player.has_played_monster_this_turn:
		return indices

	for i in range(player.hand.size()):
		var card: Dictionary = player.hand[i]
		if card.get("card_type") != CardEnums.CardType.MONSTER:
			continue
		if not _traits_overlap(card.get("traits", []), cur_traits):
			continue
		# Normal play: same rank
		if card.get("rank") == cur_rank:
			indices.append(i)
			continue
		# Burst play: card's burst rank matches current monster rank
		if _has_burst_for_rank(card, cur_rank):
			indices.append(i)
			continue
		# Alternate play cost (e.g. EBP04-012 Biollante Plant Beast Form)
		if effect_handler and effect_handler.can_monster_be_played_from_hand(player.player_id, card):
			indices.append(i)
	return indices


func check_win_condition(state: GameState) -> int:
	## Returns winner player_id, or -1 if no winner yet
	for i in range(2):
		if state.players[i].monster_zone > 8:
			# Check if opponent's zone 8 is empty (invasion victory)
			var opponent := state.players[1 - i]
			if not opponent.zone_has_battle_card(7):  # Zone 8 = index 7
				return i
	return -1


func check_counter(player: PlayerState, opponent: PlayerState) -> bool:
	## Returns true if player's counter power >= opponent's threat level
	return player.get_total_counter_power() >= opponent.get_threat_level()


func can_opponent_rank_up(opponent: PlayerState) -> bool:
	## Check if the opponent can find a valid rank-up monster from their monster deck
	var next_rank: int = opponent.current_monster.get("rank", 1) + 1
	var cur_traits: Array = opponent.current_monster.get("traits", [])

	for m in opponent.monster_deck:
		if m.get("rank") == next_rank and _traits_overlap(m.get("traits", []), cur_traits):
			return true
	return false


# --- Private helpers ---

func _can_play_any_battle_card(player: PlayerState, opponent: PlayerState) -> bool:
	var valid_zones := get_valid_zones_for_battle_card(player, opponent)
	if valid_zones.is_empty():
		return false
	for card in player.hand:
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			# Check play restrictions (e.g. EBP01-073 discard pile requirement)
			if effect_handler and not effect_handler.can_card_be_played(player.player_id, card):
				continue
			var base_rank: int = card.get("rank", 99)
			if effect_handler:
				base_rank += effect_handler.get_play_rank_modifier(player.player_id, card)
			if base_rank <= opponent.monster_zone:
				return true
			elif effect_handler:
				for zi in valid_zones:
					var zone_mod: int = effect_handler.get_zone_play_rank_modifier(player.player_id, card, zi)
					if zone_mod != 0 and base_rank + zone_mod <= opponent.monster_zone:
						return true
	return false


func _can_play_any_strategy_card(player: PlayerState) -> bool:
	if not player.has_empty_strategy_zone():
		return false
	# Check if opponent blocks strategy plays (e.g. EBP02-070)
	if effect_handler and effect_handler.are_opponent_strategy_plays_blocked(player.player_id):
		return false
	for card in player.hand:
		if card.get("card_type") == CardEnums.CardType.STRATEGY:
			var effective_rank: int = card.get("rank", 99)
			if effect_handler:
				effective_rank += effect_handler.get_play_rank_modifier(player.player_id, card)
			if effective_rank <= player.monster_zone:
				return true
	return false


func _has_monster_in_hand(player: PlayerState) -> bool:
	for card in player.hand:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			return true
	return false


func _can_play_any_monster(player: PlayerState) -> bool:
	var cur_rank: int = player.current_monster.get("rank", 0)
	var cur_traits: Array = player.current_monster.get("traits", [])

	if player.has_played_monster_this_turn:
		return false

	for card in player.hand:
		if card.get("card_type") != CardEnums.CardType.MONSTER:
			continue
		if not _traits_overlap(card.get("traits", []), cur_traits):
			continue
		if card.get("rank") == cur_rank:
			return true
		if _has_burst_for_rank(card, cur_rank):
			return true
	return false


func _has_burst_for_rank(card: Dictionary, target_rank: int) -> bool:
	## Check if a card has a Burst effect that allows playing from the given rank.
	if not effect_handler:
		return false
	var effect := effect_handler.get_effect(card)
	if not effect:
		return false
	return effect.get_burst_rank() == target_rank


func _traits_overlap(traits_a: Array, traits_b: Array) -> bool:
	for t in traits_a:
		if t in traits_b:
			return true
	return false


func _can_invade(player: PlayerState, opponent: PlayerState) -> bool:
	if player.has_invaded_this_turn:
		return false
	# Check if monster prevents its own invasion (e.g. Biollante Rose Form)
	if effect_handler and effect_handler.is_own_invasion_blocked(player.player_id):
		return false
	# Can't invade if already at zone 8 and blocked by opponent's battle card
	if player.monster_zone >= 8 and opponent.zone_has_battle_card(7):
		return false
	for card in player.hand:
		if card.get("invasion_icon", 0) > 0:
			return true
	return false
