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


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return CardEffect.monster_has_trait(owner, CardEnums.CardTrait.SECOND_FORM)


func get_burst_rank() -> int:
	return 2


func on_enter(ctx: EffectContext) -> void:
	var has_second_form: bool = CardEffect.monster_stack_has_trait(ctx.owner, CardEnums.CardTrait.SECOND_FORM)

	if not has_second_form:
		return

	var strategy_count: int = ctx.owner.count_strategies_in_play()

	for _i in range(strategy_count):
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
			tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 6)
