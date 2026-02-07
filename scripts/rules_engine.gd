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
	if _can_invade(player):
		actions.append(CardEnums.ActionType.INVADE)

	return actions


func get_playable_battle_cards(player: PlayerState, opponent: PlayerState) -> Array[int]:
	## Returns hand indices of battle cards that can be played
	var indices: Array[int] = []
	if not player.has_empty_zone():
		return indices
	for i in range(player.hand.size()):
		var card: Dictionary = player.hand[i]
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			if card.get("rank", 99) <= opponent.monster_zone:
				indices.append(i)
	return indices


func get_valid_zones_for_battle_card(player: PlayerState, opponent: PlayerState) -> Array[int]:
	## Returns zone indices (0-7) where a battle card can be placed
	## Zone must be empty and not occupied by own invading monster
	var valid: Array[int] = []
	for i in range(8):
		if player.is_zone_empty(i) and (player.monster_zone - 1) != i:
			valid.append(i)
	return valid


func can_play_battle_card_at_zone(card: Dictionary, zone_index: int, player: PlayerState, opponent: PlayerState) -> bool:
	if card.get("card_type") != CardEnums.CardType.BATTLE:
		return false
	if card.get("rank", 99) > opponent.monster_zone:
		return false
	if zone_index < 0 or zone_index >= 8:
		return false
	if not player.is_zone_empty(zone_index):
		return false
	if (player.monster_zone - 1) == zone_index:
		return false
	return true


func get_playable_strategy_cards(player: PlayerState) -> Array[int]:
	## Returns hand indices of strategy cards that can be activated
	var indices: Array[int] = []
	if not player.has_empty_strategy_zone():
		return indices
	for i in range(player.hand.size()):
		var card: Dictionary = player.hand[i]
		if card.get("card_type") == CardEnums.CardType.STRATEGY:
			if card.get("rank", 99) <= player.monster_zone:
				indices.append(i)
	return indices


func get_discardable_cards_for_invade(player: PlayerState) -> Array[int]:
	## Returns hand indices of cards that can be discarded for invasion
	var indices: Array[int] = []
	if player.has_invaded_this_turn:
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
	## Normal (same-rank) plays are limited to 1 per turn; burst plays are exempt.
	var indices: Array[int] = []
	var cur_rank: int = player.current_monster.get("rank", 0)
	var cur_traits: Array = []
	if player.current_monster.has("trait"):
		cur_traits.append(player.current_monster.get("trait"))

	if player.has_played_monster_this_turn:
		return indices

	for i in range(player.hand.size()):
		var card: Dictionary = player.hand[i]
		if card.get("card_type") != CardEnums.CardType.MONSTER:
			continue
		if not card.get("trait") in cur_traits:
			continue
		# Normal play: same rank
		if card.get("rank") == cur_rank:
			indices.append(i)
			continue
		# Burst play: card's burst rank matches current monster rank
		if _has_burst_for_rank(card, cur_rank):
			indices.append(i)
	return indices


func check_win_condition(state: GameState) -> int:
	## Returns winner player_id, or -1 if no winner yet
	for i in range(2):
		if state.players[i].monster_zone > 8:
			# Check if opponent's zone 8 is empty (invasion victory)
			var opponent := state.players[1 - i]
			if opponent.is_zone_empty(7):  # Zone 8 = index 7
				return i
	return -1


func check_counter(player: PlayerState, opponent: PlayerState) -> bool:
	## Returns true if player's counter power >= opponent's threat level
	return player.get_total_counter_power() >= opponent.get_threat_level()


func can_opponent_rank_up(opponent: PlayerState) -> bool:
	## Check if the opponent can find a valid rank-up monster from their monster deck
	var next_rank: int = opponent.current_monster.get("rank", 1) + 1
	var cur_traits: Array = []
	if opponent.current_monster.has("trait"):
		cur_traits.append(opponent.current_monster.get("trait"))

	for m in opponent.monster_deck:
		if m.get("rank") == next_rank and m.get("trait") in cur_traits:
			return true
	return false


# --- Private helpers ---

func _can_play_any_battle_card(player: PlayerState, opponent: PlayerState) -> bool:
	if not player.has_empty_zone():
		return false
	for card in player.hand:
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			if card.get("rank", 99) <= opponent.monster_zone:
				return true
	return false


func _can_play_any_strategy_card(player: PlayerState) -> bool:
	if not player.has_empty_strategy_zone():
		return false
	for card in player.hand:
		if card.get("card_type") == CardEnums.CardType.STRATEGY:
			if card.get("rank", 99) <= player.monster_zone:
				return true
	return false


func _has_monster_in_hand(player: PlayerState) -> bool:
	for card in player.hand:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			return true
	return false


func _can_play_any_monster(player: PlayerState) -> bool:
	var cur_rank: int = player.current_monster.get("rank", 0)
	var cur_traits: Array = []
	if player.current_monster.has("trait"):
		cur_traits.append(player.current_monster.get("trait"))

	if player.has_played_monster_this_turn:
		return false

	for card in player.hand:
		if card.get("card_type") != CardEnums.CardType.MONSTER:
			continue
		if not card.get("trait") in cur_traits:
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


func _can_invade(player: PlayerState) -> bool:
	if player.has_invaded_this_turn:
		return false
	for card in player.hand:
		if card.get("invasion_icon", 0) > 0:
			return true
	return false
