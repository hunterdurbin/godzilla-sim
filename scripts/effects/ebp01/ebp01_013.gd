extends CardEffect

## EBP01-013: Godzilla(Fest Godzilla) - Monster Rank 3 (Burst II)
## <Burst2> <Enter> If you have 4 or more battle cards in your zones,
## reduce your opponent's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_enter(owner: PlayerState, opponent: PlayerState) -> bool:
	if opponent.rage <= 0:
		return false
	return owner.count_zones_matching(CardUtils.is_battle) >= 4


func get_burst_rank() -> int:
	return 2


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.get_occupied_zone_indices().size() >= 4:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
