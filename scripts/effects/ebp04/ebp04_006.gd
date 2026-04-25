extends CardEffect
## EBP04-006: Godzilla (2004) - Monster Rank 4 (Red)
## <Opponent's Turn> If you have 3 or more Rank 1 strategy cards in your discard
## pile, none of your opponent's Rank 5 or lower battle cards can engage with
## this card (at the beginning of the counter phase their counter power is not
## added to the total).
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


func get_engagement_restriction(ctx: EffectContext) -> int:
	# Opponent's turn only
	if ctx.is_own_turn():
		return -1
	if _rank1_strategy_discard_count(ctx) < 3:
		return -1
	return 5


func _rank1_strategy_discard_count(ctx: EffectContext) -> int:
	var count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_strategy(card) and card.get("rank", 99) == 1:
			count += 1
	return count
