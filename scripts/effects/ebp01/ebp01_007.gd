extends CardEffect

## EBP01-007: Godzilla(1975) - Monster Rank 4 (Burst III)
## <Burst3> <When Invading> When this card <Destroy> your battle cards,
## reduce your opponent's <Rage> by 2.
##
## Tested: Yes
## Known issues: None
## Edge cases: 
##   1step, 1 crush => reduce rage x2 (works)
##   2step, 1 crush (first zone) => reduce rage x2? TODO: double check if this is intended
##   2step, 1 crush (second zone) => reduce rage x2? TODO: double check if this is intended
##   2step, 2 crush => reduce rage x4 (ability triggers twice) (works)
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func get_burst_rank() -> int:
	return 3


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	# Check if the zone the monster invaded into had a battle card (crushed during movement)
	# Zone state is captured at collection time since crush resolves before deferred abilities
	if ctx.metadata.get("zone_had_card", false):
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 2)
