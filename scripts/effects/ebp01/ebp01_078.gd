extends CardEffect

## EBP01-078: Godzilla Attacks - Strategy Rank 4 (White)
## Advance your monster card to zone 6.
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
	return owner.monster_zone < 6


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone < 6:
		await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, 6)
