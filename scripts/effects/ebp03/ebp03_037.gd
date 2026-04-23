extends CardEffect
# Godzilla(2001) (Battle R6)
# <Awakening8> <Enter> +1 rage.
# <Awakening8> +5000 CP.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "boosts_threat"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.monster_zone >= 8


func bot_can_fulfill_counter_power(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.monster_zone >= 8


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone < 8:
		return
	await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 8:
		return 5000
	return 0
