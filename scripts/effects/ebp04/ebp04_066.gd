extends CardEffect
# Gigan (2004) (Battle)
# <Opponent's Turn> If non-green battle card in own zones →
# all opp strategy cards in hand gain +2 rank (after play, return to original).


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_strategy_hand_rank_modifier(ctx: EffectContext, _card: Dictionary, target_player_id: int) -> int:
	if target_player_id == ctx.owner.player_id:
		return 0
	if ctx.game_state.current_player_id != target_player_id:
		return 0
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if zone_card.get("card_type") != CardEnums.CardType.BATTLE:
			continue
		if CardEnums.CardColor.GREEN not in zone_card.get("colors", []):
			return 2
	return 0
