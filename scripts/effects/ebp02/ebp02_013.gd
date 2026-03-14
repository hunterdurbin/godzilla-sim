extends CardEffect

## EBP02-013: Minilla(1969) - Battle Rank 5 (Red)
## <Enter> If your monster card has 2 or more <Rage>, advance your monster card to zone 5.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_monster"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.rage >= 2 and owner.monster_zone < 5


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage >= 2 and ctx.owner.monster_zone < 5:
		await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, 5)
