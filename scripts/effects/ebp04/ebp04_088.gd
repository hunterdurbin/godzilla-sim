extends CardEffect
## EBP04-088: Kidnapped Monsters - Strategy Rank 8 (Green)
## Return up to 2 non-green battle cards from your discard pile to your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["recycles_from_discard"]


func on_enter(ctx: EffectContext) -> void:
	for _i in range(2):
		var found := await ctx.effect_handler.search_discard(
			ctx.owner.player_id,
			func(card: Dictionary) -> bool:
				return (card.get("card_type") == CardEnums.CardType.BATTLE and
					CardEnums.CardColor.GREEN not in card.get("colors", [])),
			"Return a non-green battle card from your discard to hand (or skip):")
		if found.is_empty():
			break
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, found)
