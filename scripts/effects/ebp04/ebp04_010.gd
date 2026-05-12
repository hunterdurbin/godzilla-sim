extends CardEffect
## EBP04-010: Godzilla(2023) - Monster Rank 2 (Red)
## When you would set this card’s <Rage> to 0 during your start phase, if this card has
## 2 or more <Rage>, you may discard 2 cards from your hand. If you do, set this card’s
## <Rage> to 2 instead.
##
## Tested: Yes
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
	var options: Array[String] = [tr("STR_EFF_EBP04_010_CHOICE_A"), tr("STR_EFF_EBP04_010_CHOICE_B")]
	var chosen: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options, tr("STR_EFF_EBP04_010_PROMPT"))
	if chosen != 0:
		return 0
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, ctx.owner.hand.size() - 2)
	return 2
