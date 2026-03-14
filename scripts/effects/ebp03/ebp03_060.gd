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
	return opponent.rage > 0


func on_revenge(ctx: EffectContext) -> void:
	if ctx.opponent.rage > 0:
		var old_rage := ctx.opponent.rage
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)
