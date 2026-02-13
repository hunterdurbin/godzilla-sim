extends CardEffect

## EBP02-006: Godzilla(2016) 4th Form - Monster Rank 4 (Red)
## <When Invading> If there is a card with <3rd Form> under this card,
## <Destroy> all of your opponent's rank 6 or lower battle cards.
## If there is a <4th Form> card under this card, this card gains +10,000 threat level
## for each strategy card in your strategy zone.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	var has_third_form: bool = false
	for card in ctx.owner.monster_stack:
		var traits: Array = card.get("traits", [])
		if CardEnums.CardTrait.THIRD_FORM in traits:
			has_third_form = true
			break

	if has_third_form:
		var zones_to_destroy: Array[int] = []
		for i in range(8):
			var zone_card := ctx.opponent.get_zone_top_card(i)
			if not zone_card.is_empty() and zone_card.get("rank", 0) <= 6:
				zones_to_destroy.append(i)
		if not zones_to_destroy.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	var has_fourth_form: bool = false
	for card in ctx.owner.monster_stack:
		var traits: Array = card.get("traits", [])
		if CardEnums.CardTrait.FOURTH_FORM in traits:
			has_fourth_form = true
			break

	if not has_fourth_form:
		return 0

	var strategy_count: int = 0
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty():
			strategy_count += 1
	return strategy_count * 10000
