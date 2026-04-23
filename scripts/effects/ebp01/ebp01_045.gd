extends CardEffect

## EBP01-045: Meganula - Battle Rank 2 (Blue)
## <Enter> If this card is in the same column as your opponent's monster card and you
## have 2 or more battle cards in your zones, reduce your opponent's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["column_dependent_monster", "weakens_opponent"]


func bot_can_fulfill_on_enter(owner: PlayerState, opponent: PlayerState) -> bool:
	if opponent.rage <= 0:
		return false
	return owner.count_zones_matching(CardUtils.is_battle) >= 2


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var opp_columns := get_opponent_column_zones(zone_idx)
	if (ctx.opponent.monster_zone - 1) not in opp_columns:
		return

	if ctx.owner.get_occupied_zone_indices().size() < 2:
		return

	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
