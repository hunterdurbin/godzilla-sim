extends CardEffect
# Godzilla(2001) (Battle R6)
# <Awakening8> <Enter> Increase your monster card’s <Rage> by 1.
# <Awakening8> This card gains +5000 counter power.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "boosts_threat"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.is_awakening(8)


func bot_can_fulfill_counter_power(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.is_awakening(8)


func on_enter(ctx: EffectContext) -> void:
	if not ctx.is_awakening(8):
		return
	await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1, ctx.card_data.get("id", ""))


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.is_awakening(8):
		return 5000
	return 0
