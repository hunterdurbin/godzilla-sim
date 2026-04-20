extends CardEffect
# MOGERA
# <Enter> May swap zones of any 2 battle cards in own zones.


func get_bot_tags() -> Array[String]:
	return ["zone_dependent"]


func on_enter(ctx: EffectContext) -> void:
	var occupied: Array[int] = []
	for i in range(8):
		if ctx.owner.zone_has_cards(i):
			occupied.append(i)
	if occupied.size() < 2:
		return

	var zone_a: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, occupied,
		"Choose the first battle card to swap (or skip):", true)
	if zone_a < 0:
		return

	var remaining: Array[int] = occupied.filter(func(z): return z != zone_a)
	if remaining.is_empty():
		return

	var zone_b: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, remaining,
		"Choose the second battle card to swap with:")
	if zone_b < 0:
		return

	var stack_a: Array = ctx.owner.zones[zone_a].duplicate()
	var stack_b: Array = ctx.owner.zones[zone_b].duplicate()
	ctx.owner.zones[zone_a] = stack_b
	ctx.owner.zones[zone_b] = stack_a
	ctx.owner.zones_changed.emit()
