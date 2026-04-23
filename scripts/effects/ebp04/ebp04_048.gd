extends CardEffect
## EBP04-048: Little Godzilla - Battle Rank 5 (Blue)
## Your in play strategy cards cannot be <Destroy> by your opponents effects.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["protects_cards"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func protects_card_from_destruction(ctx: EffectContext, card_data: Dictionary, _zone_idx: int) -> bool:
	# Protects strategy cards in strategy zones from opponent destruction effects
	# Note: this is called from strategy zone destruction checks, not zone_idx
	return CardUtils.is_strategy(card_data)
