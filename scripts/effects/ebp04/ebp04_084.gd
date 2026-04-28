extends CardEffect
## EBP04-084: Atomic Beam - Strategy Rank 1 (Green)
## <Destroy> all of your opponent's battle cards in the same column as your
## monster card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_monster_self"]


func on_enter(ctx: EffectContext) -> void:
	var targetable := ctx.get_opponent_column_zones_with_cards(ctx.owner.monster_zone - 1)
	if targetable.is_empty():
		return
	await ctx.effect_handler.destroy_zones(ctx.opponent, targetable)
