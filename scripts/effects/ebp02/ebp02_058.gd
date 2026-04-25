extends CardEffect

## EBP02-058: Dorat - Battle Rank 2 (Green)
## <Revenge> Return up to 1 <King Ghidorah> monster card from your discard pile
## to your hand.
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
			return CardUtils.has_trait(card, CardEnums.CardTrait.KING_GHIDORAH),
		tr("STR_EFF_EBP02_058_PROMPT"))

	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
