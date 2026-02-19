extends CardEffect

## EBP02-004: Godzilla(2016) 3rd Form - Monster Rank 3 (Red)
## <Burst2>
## <Enter> If there is a <2nd Form> card under this card, <Destroy> 1 of your opponent's
## rank 6 or lower battle cards for each strategy card in your strategy zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_burst_rank() -> int:
	return 2


func on_enter(ctx: EffectContext) -> void:
	var has_second_form: bool = false
	for card in ctx.owner.monster_stack:
		var traits: Array = card.get("traits", [])
		if CardEnums.CardTrait.SECOND_FORM in traits:
			has_second_form = true
			break

	if not has_second_form:
		return

	var strategy_count: int = 0
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty():
			strategy_count += 1

	for _i in range(strategy_count):
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
			"Choose an opponent's rank 6 or lower battle card to destroy:")
