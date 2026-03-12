extends CardEffect

## ESD01-016: Heat Ray - Strategy Rank 1
## <Destroy> all of your opponent's battle cards in the same column as your monster card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_monster"]


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1 # 0-indexed
	var column_zones := get_opponent_column_zones(monster_zone_idx)
	await ctx.effect_handler.destroy_zones(ctx.opponent, column_zones)
