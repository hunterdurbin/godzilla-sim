extends CardEffect

## EFC01-004: Hedorah(2021) - Battle Rank 8 (Red)
## When playing this card from your hand, you can reduce its rank by 1 for each battle
## card in your opponent's zones. (After being played this card is rank 8)
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
	var count: int = ctx.opponent.count_zones_matching(CardUtils.is_battle)
	return -count
