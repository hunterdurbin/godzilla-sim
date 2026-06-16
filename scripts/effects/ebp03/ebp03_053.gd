extends CardEffect

## EBP03-053: Super Mechagodzilla - Battle Rank 8 (Blue)
## While your opponent’s <Rage> is 0, this card cannot be <Destroy> by opponent’s
## effects.
## If this card is in the same column as your opponent’s monster card, this card gains
## +3000 counter power for each of your opponent’s <Rage> .
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"can_be_destroyed": {"caused_by_opponent": true},
}


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "column_dependent_monster"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func can_be_destroyed(ctx: EffectContext) -> bool:
	# Cannot be destroyed while opponent's rage is 0
	if not ctx.opponent_has_rage():
		return false
	return true


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return 0

	# Check if same column as opponent's monster
	var opp_monster_zone_idx: int = ctx.opponent.monster_zone - 1
	var my_column_zones: Array[int] = get_opponent_column_zones(my_zone)
	if opp_monster_zone_idx not in my_column_zones:
		return 0

	return 3000 * ctx.opponent.rage
