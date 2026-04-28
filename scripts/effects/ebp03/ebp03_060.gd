extends CardEffect
# Mothra(imago)(1961) (Battle R5)
# <Revenge> Reduce opponent rage by 1.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_revenge(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.has_rage()


func on_revenge(ctx: EffectContext) -> void:
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
