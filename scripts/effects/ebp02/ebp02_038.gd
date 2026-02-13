extends CardEffect

## EBP02-038: Godzilla 2000: Millennium - Strategy Rank 2 (Blue)
## Choose one of the following:
## - <Destroy> 1 of your opponent's rank 5 or lower battle cards.
## - If you have 10 or more monster cards in your discard pile,
##   <Destroy> 1 of your opponent's battle cards in zone 8.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var monster_count: int = 0
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			monster_count += 1

	if monster_count >= 10:
		# Offer zone 8 option if there's a card there
		var opp_z8 := ctx.opponent.get_zone_top_card(7)
		if not opp_z8.is_empty():
			var chosen: int = await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.opponent.player_id, [7],
				"Destroy zone 8 card? (Skip for rank 5 or lower instead):", true)
			if chosen >= 0:
				await ctx.effect_handler.destroy_zones(ctx.opponent, [7])
				return

	# Default: destroy 1 rank 5 or lower
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return card.get("rank", 0) <= 5,
		"Choose an opponent's rank 5 or lower battle card to destroy:")
