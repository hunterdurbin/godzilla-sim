extends CardEffect

## EBP02-075: Chibi Mothra - Battle Rank 3 (White)
## <Enter> If a card named "Chibi Mechagodzilla" is in your zones,
## reduce your opponent's <Rage> by 1.
##
## Tested: No
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
	return owner.has_zone_matching(
		func(c: Dictionary) -> bool: return c.get("name", "") == "Chibi Mechagodzilla")


func on_enter(ctx: EffectContext) -> void:
	var has_mechagodzilla: bool = ctx.owner.has_zone_matching(
		func(c: Dictionary) -> bool: return c.get("name", "") == "Chibi Mechagodzilla")

	if has_mechagodzilla:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
