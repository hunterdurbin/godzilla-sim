extends CardEffect
## EBP04-071: Kamoebas (1970) - Battle Rank 5 (White)
## <Awakening 4> If this is in the same column as your opponent's red monster
## card, this gains +5000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "column_dependent_monster"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone < 4:
		return 0
	if not CardUtils.has_color(ctx.opponent.current_monster, CardEnums.CardColor.RED):
		return 0
	if _is_in_opponent_monster_column(ctx):
		return 5000
	return 0


func _is_in_opponent_monster_column(ctx: EffectContext) -> bool:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return false
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	return opp_monster_idx in get_opponent_column_zones(zone_idx)
