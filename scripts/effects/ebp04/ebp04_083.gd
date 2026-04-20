extends CardEffect
# Godzilla vs. Destoroyah
# Destroy all opp battle cards in zones 6-8.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	for i in range(5, 8):
		if opponent.zone_has_cards(i):
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var zones_to_destroy: Array[int] = []
	for i in range(5, 8):  # zones 6-8 = indices 5-7
		if ctx.opponent.zone_has_cards(i):
			zones_to_destroy.append(i)
	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
