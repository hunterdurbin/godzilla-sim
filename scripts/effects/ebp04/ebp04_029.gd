extends CardEffect
## EBP04-029: Gigan (2004) - Monster Rank 3 (Green)
## Your opponent cannot discard a <Invade 1> card to invade.
## <Enter> If your opponent's monster card is in Zones 1-5, you may return up to
## 1 <Gigan> monster card from your discard pile to your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func blocks_invade1_invasion_cost(_ctx: EffectContext) -> bool:
	return true


func get_bot_tags() -> Array[String]:
	return ["blocks_invade"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.monster_zone > 5:
		return

	var found := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if not CardUtils.is_monster(card):
				return false
			return CardUtils.has_trait(card, CardEnums.CardTrait.GIGAN),
		tr("STR_EFF_EBP04_029_PROMPT"))

	if not found.is_empty():
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, found)
