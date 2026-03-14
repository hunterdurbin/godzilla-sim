extends CardEffect

## EBP03-039: Godzilla(2016) 4th Form - Battle Rank 7 (Red)
## Whenever your card is sent from a strategy zone to the discard pile, draw 1 card.
## If there are 5 or more strategy cards in your discard pile, this card gains +5000 CP.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards", "boosts_cp"]


func bot_can_fulfill_counter_power(owner: PlayerState, _opponent: PlayerState) -> bool:
	var strategy_count: int = 0
	for card in owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.STRATEGY:
			strategy_count += 1
			if strategy_count >= 5:
				return true
	return false


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_strategy_discarded(ctx: EffectContext, _strategy_card: Dictionary) -> void:
	ctx.owner.draw_cards(1)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var strategy_count: int = 0
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.STRATEGY:
			strategy_count += 1
	if strategy_count >= 5:
		return 5000
	return 0
