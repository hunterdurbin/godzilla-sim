extends CardEffect
## EBP04-063: Godzilla Filius - Battle Rank 5 (Green)
## <Revenge> Return up to 1 [Godzilla Earth] battle card from your discard pile
## to your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func on_revenge(ctx: EffectContext) -> void:
	var found := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if not CardUtils.is_battle(card):
				return false
			return CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA_EARTH),
		tr("STR_EFF_EBP04_063_PROMPT"))
	if not found.is_empty():
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, found)
