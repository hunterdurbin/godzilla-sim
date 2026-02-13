extends CardEffect

## EBP02-008: Godzilla(1969) - Monster Rank 3 (Red)
## <Burst4>
## Whenever this card's <Rage> is increased, <Destroy> all of your opponent's rank 6 or
## lower battle cards in the zone with the same number as the zone this card occupies.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_burst_rank() -> int:
	return 4


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	if new_rage <= old_rage:
		return

	# Monster is in monster_zone (1-indexed), opponent's same zone number = monster_zone - 1 (0-indexed)
	var zone_idx: int = ctx.owner.monster_zone - 1
	var opp_zone_card := ctx.opponent.get_zone_top_card(zone_idx)
	if not opp_zone_card.is_empty() and opp_zone_card.get("rank", 0) <= 6:
		await ctx.effect_handler.destroy_zones(ctx.opponent, [zone_idx])
