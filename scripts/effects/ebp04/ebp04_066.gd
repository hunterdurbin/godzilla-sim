extends CardEffect
## EBP04-066: Gigan (2004) - Battle Rank 7 (Green)
## <Opponent's Turn> If there is a Battle card in your zones that is not green,
## all strategy cards in your opponent's hand gain +2 in rank (after play they
## return to their original rank).
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


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
