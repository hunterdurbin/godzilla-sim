extends CardEffect

## EBP02-016: Anguirus(2004) - Battle Rank 7 (Red)
## If this card is in the same column as the opponent's monster card,
## this card gains +5000 counter power.
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
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	var opp_columns := get_opponent_column_zones(zone_idx)
	if opp_monster_idx in opp_columns:
		return 5000
	return 0
