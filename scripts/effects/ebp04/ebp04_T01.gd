extends CardEffect
# Godzilla Earth Token
# If this token is destroyed or moved, destroy EBP04-067 in zone 8.


func on_destroy(ctx: EffectContext, _zone_idx: int) -> void:
	var card: Dictionary = ctx.owner.get_zone_top_card(7)
	if card.get("id") == "EBP04-067":
		await ctx.effect_handler.destroy_zones(ctx.owner, [7])


func on_zone_changed(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	var card: Dictionary = ctx.owner.get_zone_top_card(7)
	if card.get("id") == "EBP04-067":
		await ctx.effect_handler.destroy_zones(ctx.owner, [7])
