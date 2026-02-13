extends CardEffect

## EBP02-013: Minilla(1969) - Battle Rank 5 (Red)
## <Enter> If your monster card has 2 or more <Rage>, advance your monster card to zone 5.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage >= 2 and ctx.owner.monster_zone < 5:
		var old_zone: int = ctx.owner.monster_zone
		ctx.owner.monster_zone = 5
		ctx.owner.monster_changed.emit()
		await ctx.effect_handler.trigger_monster_advance(ctx.owner.player_id, old_zone, 5)
