extends CardEffect

## EBP02-062: SpaceGodzilla - Battle Rank 5 (Green)
## <Revenge> Return up to 1 <《SpaceGodzilla》> monster card from your discard pile to
## your hand. (Activates when destroyed by a card effect or monster card movement.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func on_revenge(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if not CardUtils.is_monster(card):
				return false
			return CardUtils.has_trait(card, CardEnums.CardTrait.SPACEGODZILLA),
		tr("STR_EFF_EBP02_062_PROMPT"))

	if not selected.is_empty():
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, selected)
