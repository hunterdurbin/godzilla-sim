extends CardEffect
# Rainbow Mothra (Battle R7)
# <Enter> If Base in play, opponent monster with TL <= 20000 retreats 1 zone.
# (Also has Evolution8 Mothra — handled by card data fields.)


func on_enter(ctx: EffectContext) -> void:
	if not _has_base_in_play(ctx):
		return

	var opp_tl: int = ctx.opponent.current_monster.get("threat_level", 0) + ctx.opponent.rage * 5000
	opp_tl += ctx.effect_handler.get_threat_level_modifier(ctx.opponent.player_id)

	if opp_tl > 20000:
		return

	if ctx.opponent.monster_zone <= 1:
		return

	var old_zone := ctx.opponent.monster_zone
	ctx.opponent.monster_zone -= 1
	ctx.opponent.monster_changed.emit()
	await ctx.effect_handler.trigger_monster_advance(ctx.opponent.player_id, old_zone, ctx.opponent.monster_zone)


func _has_base_in_play(ctx: EffectContext) -> bool:
	for strategy in ctx.owner.strategy_zones:
		if not strategy.is_empty() and strategy.get("is_base", false):
			return true
	return false
