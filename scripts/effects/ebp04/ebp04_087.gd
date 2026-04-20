extends CardEffect
# Beginning of the Two
# Destroy up to 1 red, blue, green, and white battle card each in opp's zones 1-5.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_enter(ctx: EffectContext) -> void:
	var colors: Array[CardEnums.CardColor] = [
		CardEnums.CardColor.RED,
		CardEnums.CardColor.BLUE,
		CardEnums.CardColor.GREEN,
		CardEnums.CardColor.WHITE,
	]

	for color in colors:
		var valid_zones: Array[int] = []
		for i in range(5):  # zones 1-5 = indices 0-4
			var zone_card := ctx.opponent.get_zone_top_card(i)
			if zone_card.is_empty():
				continue
			if color in zone_card.get("colors", []):
				valid_zones.append(i)
		if valid_zones.is_empty():
			continue

		var chosen: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.opponent.player_id, valid_zones,
			"Destroy an opponent's %s battle card in zones 1-5 (or skip):" % CardEnums.color_to_string(color),
			true)
		if chosen >= 0:
			await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
