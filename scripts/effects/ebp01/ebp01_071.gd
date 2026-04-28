extends CardEffect

## EBP01-071: Giant Condor - Battle Rank 5 (White)
## If this card is in the same column as your opponent's monster card, this card gains
## +5000 counter power.
## When your opponent's <Rage> is increased, <Destroy> this card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_opponent_rage_changed": {"direction": "increase"},
}


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "column_dependent_monster"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	var opp_columns := get_opponent_column_zones(zone_idx)
	if (ctx.opponent.monster_zone - 1) in opp_columns:
		return 5000
	return 0


func on_opponent_rage_changed(ctx: EffectContext, _old_rage: int, _new_rage: int) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return
	await ctx.effect_handler.destroy_zones(ctx.owner, [zone_idx] as Array[int])
