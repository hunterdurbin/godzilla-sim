extends CardEffect

## EBP02-006: Godzilla(2016) 4th Form - Monster Rank 4 (Red)
## <When Invading> If there is a card with <《3rd Form》> under this card, <Destroy> all
## of your opponent's rank 6 or lower battle cards.
## If there is a <《4th Form》> card under this card, this card gains +10,000 threat level
## for each strategy card in your strategy zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "boosts_threat"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func bot_can_fulfill_on_when_invading(owner: PlayerState, _opponent: PlayerState) -> bool:
	return CardEffect.monster_has_trait(owner, CardEnums.CardTrait.THIRD_FORM)


func bot_can_fulfill_threat_level(owner: PlayerState, _opponent: PlayerState) -> bool:
	return CardEffect.monster_has_trait(owner, CardEnums.CardTrait.FOURTH_FORM)


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	var has_third_form: bool = CardEffect.monster_stack_has_trait(ctx.owner, CardEnums.CardTrait.THIRD_FORM)

	if has_third_form:
		var zones_to_destroy: Array[int] = ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 6)
		if not zones_to_destroy.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	var has_fourth_form: bool = CardEffect.monster_stack_has_trait(ctx.owner, CardEnums.CardTrait.FOURTH_FORM)

	if not has_fourth_form:
		return 0

	var strategy_count: int = ctx.owner.count_strategies_in_play()
	return strategy_count * 10000
