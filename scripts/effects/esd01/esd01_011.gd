extends CardEffect

## ESD01-011: Godzilla(2023) - Battle Rank 5
## <Enter> If your monster card has 2 or more <Rage> , reduce your opponent's <Rage> by
## 1.
## When this card is <Destroy> , place this card on the bottom of your deck instead.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: Replacement effect — the card never counts as destroyed (no revenge);
## applies to effect destroys, crush (11.3), and overload (11.5).
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "heals_deck"]


func bot_can_fulfill_on_enter(owner: PlayerState, opponent: PlayerState) -> bool:
	return owner.rage >= 2 and opponent.has_rage()


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage >= 2:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)


func on_would_be_destroyed(_ctx: EffectContext) -> bool:
	# Move to deck bottom instead of being destroyed
	return true
