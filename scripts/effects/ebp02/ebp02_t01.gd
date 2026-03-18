extends CardEffect

## EBP02-T01: Conductorless Train Bombers - Token Battle Rank 2 (Red)
## <Enter> Reduce your opponent's <Rage> by 1.
## (Tokens cannot be added to the deck. They are banished when removed from zones.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
