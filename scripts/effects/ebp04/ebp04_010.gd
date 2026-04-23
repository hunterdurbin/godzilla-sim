extends CardEffect
## EBP04-010: Godzilla (2023) - Monster Rank 2 (Red)
## During your start phase, when you would set this card's <Rage> to 0, if its
## <Rage> is 2 or higher you may discard 2 cards from your hand to set its
## <Rage> to 2 instead.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["retains_rage"]


func on_rage_reset(ctx: EffectContext) -> int:
	if ctx.owner.rage < 2:
		return 0
	if ctx.owner.hand.size() < 2:
		return 0
	var options: Array[String] = ["Discard 2 cards (set rage to 2)", "Let rage reset to 0"]
	var chosen: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options, "Rage would reset to 0. Discard 2 cards to keep rage at 2?")
	if chosen != 0:
		return 0
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, ctx.owner.hand.size() - 2)
	return 2
