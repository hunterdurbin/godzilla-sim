extends CardEffect

## EBP01-047: Orga - Battle Rank 3 (Blue)
## <Enter> Draw 1 card, then discard 1 card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func on_enter(ctx: EffectContext) -> void:
	ctx.owner.draw_cards(1)
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, ctx.owner.hand.size() - 1)
