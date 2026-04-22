extends CardEffect
# Kaiser Ghidorah (Battle)
# <Your Turn> If no strategies in play → strategy cards in hand gain -1 rank per color in discard.


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_strategy_hand_rank_modifier(ctx: EffectContext, card: Dictionary, target_player_id: int) -> int:
	# Only affects own strategies, only on own turn
	if target_player_id != ctx.owner.player_id:
		return 0
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	# Only applies to strategy cards in hand
	if card.get("card_type") != CardEnums.CardType.STRATEGY:
		return 0
	# Only if no strategies currently in play
	var has_strategy := false
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty():
			has_strategy = true
			break
	if has_strategy:
		return 0
	# Count distinct colors in discard
	var colors_seen: Array = []
	for discard_card in ctx.owner.discard_pile:
		for color in discard_card.get("colors", []):
			if color not in colors_seen:
				colors_seen.append(color)
	return -colors_seen.size()
