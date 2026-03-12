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


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone < 6:
		return

	ctx.owner.draw_cards(2)

	for _i in range(2):
		if ctx.owner.hand.is_empty():
			break
		await ctx.effect_handler.select_hand_card(
			ctx.owner.player_id,
			func(_card: Dictionary) -> bool: return true,
			"Choose a card to discard:"
		)
