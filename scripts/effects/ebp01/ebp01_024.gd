extends CardEffect

## EBP01-024: Minilla(2004) - Battle Rank 6
## <Enter> Reduce your opponent's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.has_rage()


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
