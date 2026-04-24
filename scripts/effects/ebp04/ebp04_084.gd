extends CardEffect
## EBP04-084: Atomic Beam - Strategy Rank 1 (Green)
## <Destroy> all of your opponent's battle cards in the same column as your
## monster card.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_monster_self"]


func on_enter(ctx: EffectContext) -> void:
	var monster_idx: int = ctx.owner.monster_zone - 1
	var col_zones := get_opponent_column_zones(monster_idx)
	var targetable: Array[int] = []
	for zi in col_zones:
		if ctx.opponent.zone_has_cards(zi):
			targetable.append(zi)
	if targetable.is_empty():
		return
	await ctx.effect_handler.destroy_zones(ctx.opponent, targetable)
