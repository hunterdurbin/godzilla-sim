extends CardEffect
# Godzilla Captured! (Strategy R7)
# Set opponent's rage to 0.
#
# Tested: No, Looks good at glance
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func on_enter(ctx: EffectContext) -> void:
	if ctx.opponent.rage == 0:
		return
	var old_rage := ctx.opponent.rage
	ctx.opponent.rage = 0
	ctx.opponent.rage_changed.emit(ctx.opponent.rage)
	await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, 0)
