extends CardEffect
# Godzilla(2001) (Battle R6)
# <Awakening8> <Enter> +1 rage.
# <Awakening8> +5000 CP.


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone < 8:
		return
	var old_rage := ctx.owner.rage
	ctx.owner.rage += 1
	ctx.owner.rage_changed.emit(ctx.owner.rage)
	await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.monster_zone >= 8:
		return 5000
	return 0
