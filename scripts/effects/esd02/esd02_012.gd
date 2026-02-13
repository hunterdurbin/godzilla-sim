extends CardEffect

## ESD02-012: Mechagodzilla(1993) - Battle Rank 7
## If your opponent's monster card is rank IV or higher, this card gains +5000 counter power.
## If this card is in the same column as your opponent's monster card, this card gains +3000 counter power.
## (If both conditions are met, this card gains +8000 counter power.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var bonus := 0

	# +5000 if opponent's monster is rank IV or higher
	if ctx.opponent.get_monster_rank() >= 4:
		bonus += 5000

	# +3000 if in the same column as opponent's monster
	var my_zone := find_zone_of_card(ctx)
	if my_zone >= 0:
		var opp_monster_idx: int = ctx.opponent.monster_zone - 1
		if opp_monster_idx >= 0:
			var facing_zones := get_opponent_column_zones(my_zone)
			if opp_monster_idx in facing_zones:
				bonus += 3000

	return bonus
