extends CardEffect

## ESD01-016: Heat Ray - Strategy Rank 1
## <Destroy> all of your opponent's battle cards in the same column as your monster card.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1 # 0-indexed
	var column_zones := get_opponent_column_zones(monster_zone_idx)
	ctx.effect_handler.destroy_zones(ctx.opponent, column_zones)
