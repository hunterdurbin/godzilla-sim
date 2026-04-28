extends CardEffect
## EBP04-087: Beginning of the Two - Strategy Rank 5 (Green)
## <Destroy> up to 1 red, blue, green, and white battle cards each in your
## opponent's zones 1-5.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_enter(ctx: EffectContext) -> void:
	# Pool of color slots that haven't been filled yet. Each pick consumes
	# one color (the first matching color on the chosen card). The player
	# selects all targets first; destruction happens after, in pick order.
	var pool: Array[int] = [
		CardEnums.CardColor.RED,
		CardEnums.CardColor.BLUE,
		CardEnums.CardColor.GREEN,
		CardEnums.CardColor.WHITE,
	]
	var picks: Array[int] = []

	while not pool.is_empty():
		var valid_zones: Array[int] = []
		for i in range(5): # zones 1-5 = indices 0-4
			if i in picks:
				continue
			var zone_card := ctx.opponent.get_zone_top_card(i)
			if zone_card.is_empty() or not CardUtils.is_battle(zone_card):
				continue
			for c: int in zone_card.get("colors", []):
				if c in pool:
					valid_zones.append(i)
					break
		if valid_zones.is_empty():
			break

		var chosen: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.opponent.player_id, valid_zones,
			tr("STR_EFF_EBP04_087_PROMPT"), true)
		if chosen < 0:
			break

		picks.append(chosen)
		var picked_card := ctx.opponent.get_zone_top_card(chosen)
		for c: int in picked_card.get("colors", []):
			if c in pool:
				pool.erase(c)
				break

	for zone in picks:
		await ctx.effect_handler.destroy_zones(ctx.opponent, [zone])
