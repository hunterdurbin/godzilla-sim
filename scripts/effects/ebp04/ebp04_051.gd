extends CardEffect
## EBP04-051: Super Mechagodzilla - Battle Rank 6 (Blue)
## <Enter> If this is in the same column as your opponent's monster card,
## your opponent's 30,000 or less threat monster card retreats back 1 zone.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["retreats_opponent", "column_dependent_monster"]


func on_enter(ctx: EffectContext) -> void:
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return

	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	var col_zones := get_opponent_column_zones(my_zone)
	if opp_monster_idx not in col_zones:
		return

	if ctx.opponent.monster_zone <= 1:
		return

	var opp_tl: int = ctx.effect_handler.get_effective_threat_level(ctx.opponent.player_id)
	if opp_tl > 30000:
		return

	await ctx.effect_handler.retreat_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
