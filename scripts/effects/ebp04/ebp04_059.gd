extends CardEffect
## EBP04-059: Rodan (2021) - Battle Rank 4 (Green)
## You may have any number of this card in your deck.
## <Revenge> If you have 5 or more green battle cards in your discard pile, you may
## return up to 1 battle card with 《Rodan》 from your discard pile to your hand.
## (Activates when destroyed by a card effect or monster card movement. You may target
## this card to be returned to your hand.)
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
	var green_count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card) and CardUtils.has_color(card, CardEnums.CardColor.GREEN):
			green_count += 1
	if green_count < 5:
		return

	var found := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if not CardUtils.is_battle(card):
				return false
			return CardUtils.has_trait(card, CardEnums.CardTrait.RODAN),
		tr("STR_EFF_EBP04_059_PROMPT"))
	if not found.is_empty():
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, found)
