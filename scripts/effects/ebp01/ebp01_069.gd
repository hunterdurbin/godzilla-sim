extends CardEffect

## EBP01-069: Varan - Battle Rank 4 (White)
## <Awakening6> <Enter> Draw 2 cards, then discard 2 cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.is_awakening(6)


func on_enter(ctx: EffectContext) -> void:
	if not ctx.is_awakening(6):
		return

	ctx.owner.draw_cards(2)
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, ctx.owner.hand.size() - 2)
