extends CardEffect

## EBP03-071: Godzilla's Skeleton - Strategy Rank 8 (Red)
## When counting monster cards in your discard pile, treat this card as a monster card
## as well.
## Look at the top 4 cards of your deck, put any number of them on top of your deck in
## any order, send the rest to your discard pile, then draw 2 cards.
##
## Note: "counts_as_monster_in_discard" flag is set in the card data (scripts/cards/sets/).
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards", "mill_self"]


func on_enter(ctx: EffectContext) -> void:
	# Empty deck: no look, but still draw (the draw reshuffles the discard).
	await ctx.effect_handler.arrange_deck_top(
		ctx.owner.player_id, 4, tr("STR_EFF_DECK_ARRANGE_TOP"))
	ctx.owner.draw_cards(2)
