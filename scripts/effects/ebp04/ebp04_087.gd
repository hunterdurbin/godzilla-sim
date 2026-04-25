extends CardEffect
## EBP04-087: Beginning of the Two - Strategy Rank 5 (Green)
## <Destroy> up to 1 red, blue, green, and white battle cards each in your
## opponent's zones 1-5.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


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
			if CardUtils.has_color(zone_card, color):
				valid_zones.append(i)
		if valid_zones.is_empty():
			continue

		var chosen: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.opponent.player_id, valid_zones,
			tr("STR_EFF_DESTROY_OPP_COLOR_ZONES_1_5_FMT") % CardEnums.color_to_string(color),
			true)
		if chosen >= 0:
			await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
