extends CardEffect

## EFC01-004: Hedorah(2021) - Battle Rank 8 (Red)
## When playing this card from your hand, this card's rank is reduced by 1 for each
## of your opponent's battle cards in zones. (Rank stays 8 on the field.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	# Only modifies self
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	# Count opponent battle cards in zones
	var count: int = 0
	for i in range(8):
		var card := ctx.opponent.get_zone_top_card(i)
		if not card.is_empty() and card.get("card_type") == CardEnums.CardType.BATTLE:
			count += 1
	return -count
