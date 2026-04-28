extends CardEffect
## EBP04-065: Godzilla Earth - Battle Rank 6 (Green)
## If this card is in the same column as your opponent's monster card, this card
## gains +3000 counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "column_dependent_monster"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if _is_in_opponent_monster_column(ctx):
		return 3000
	return 0


func _is_in_opponent_monster_column(ctx: EffectContext) -> bool:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return false
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	return opp_monster_idx in get_opponent_column_zones(zone_idx)
