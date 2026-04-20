extends CardEffect
# Kaiser Ghidorah (Battle)
# <Enter> Destroy opp battle cards from lowest zone, count = # colors in discard.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_enter(ctx: EffectContext) -> void:
	var color_count: int = _count_discard_colors(ctx)
	if color_count == 0:
		return

	for _i in range(color_count):
		# Find lowest-numbered zone with a battle card
		var target_zone: int = -1
		for zi in range(8):
			if ctx.opponent.zone_has_cards(zi):
				target_zone = zi
				break
		if target_zone < 0:
			break
		await ctx.effect_handler.destroy_zones(ctx.opponent, [target_zone])


func _count_discard_colors(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			for c: int in card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size()
