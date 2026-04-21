extends CardEffect
# Godzilla Earth (Battle)
# Can only be played in area 8.
# <Enter> Play 1 [Godzilla Earth] Token in own area 3.
# If this card or token are moved/not in zone, Destroy both.


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func get_required_play_zones(_ctx: EffectContext) -> Array[int]:
	return [7]  # Zone 8 only (index 7)


func on_enter(ctx: EffectContext) -> void:
	var top: Dictionary = ctx.owner.get_zone_top_card(2)
	if top.get("card_type") == CardEnums.CardType.MONSTER:
		return
	await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP04-T01", 2)


func on_destroy(ctx: EffectContext, _zone_idx: int) -> void:
	# Destroy linked token in zone 3 when this card is destroyed
	var token: Dictionary = ctx.owner.get_zone_top_card(2)
	if token.get("id") == "EBP04-T01":
		await ctx.effect_handler.destroy_zones(ctx.owner, [2])


func on_zone_changed(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	# Destroy linked token in zone 3 when this card is moved
	var token: Dictionary = ctx.owner.get_zone_top_card(2)
	if token.get("id") == "EBP04-T01":
		await ctx.effect_handler.destroy_zones(ctx.owner, [2])
