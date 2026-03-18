extends CardEffect

## ESD01-011: Godzilla(2023) - Battle Rank 5
## <Enter> If your monster card has 2 or more <Rage>, reduce your opponent's <Rage> by 1.
## When this card is <Destroy>, place this card on the bottom of your deck instead.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "heals_deck"]


func bot_can_fulfill_on_enter(owner: PlayerState, opponent: PlayerState) -> bool:
	return owner.rage >= 2 and opponent.rage > 0


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage >= 2:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)


func on_revenge(ctx: EffectContext) -> void:
	ctx.effect_handler.return_to_deck_bottom(ctx.owner, ctx.card_data)


func on_crush(ctx: EffectContext) -> void:
	ctx.effect_handler.return_to_deck_bottom(ctx.owner, ctx.card_data)
