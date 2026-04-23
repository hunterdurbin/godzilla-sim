extends CardEffect
## EBP04-055: Higher Dimensional Monster Ghidorah - Battle Rank 1 (Green)
## <Enter> You may <Destroy> 4 other green battle cards in your zones. If you
## don't do so, <Destroy> this.
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
	var my_zone: int = find_zone_of_card(ctx)

	# Count eligible green battle cards (excluding self)
	var green_zones: Array[int] = []
	for i in range(8):
		if i == my_zone:
			continue
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if (zone_card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardColor.GREEN in zone_card.get("colors", [])):
			green_zones.append(i)

	if green_zones.size() < 4:
		# Can't pay cost, destroy self
		if my_zone >= 0:
			await ctx.effect_handler.destroy_zones(ctx.owner, [my_zone])
		return

	var options: Array[String] = [
		"Destroy 4 green battle cards in your zones",
		"Skip (this card will be Destroyed)",
	]
	var chosen: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options, "Choose:")

	if chosen == 1:
		if my_zone >= 0:
			await ctx.effect_handler.destroy_zones(ctx.owner, [my_zone])
		return

	# Player must choose 4 green zones to destroy
	var to_destroy: Array[int] = []
	var remaining_green: Array[int] = green_zones.duplicate()

	for _i in range(4):
		if remaining_green.is_empty():
			break
		var picked: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, remaining_green,
			"Choose a green battle card to Destroy (%d remaining):" % (4 - to_destroy.size()))
		if picked < 0:
			break
		to_destroy.append(picked)
		remaining_green.erase(picked)

	if to_destroy.size() == 4:
		await ctx.effect_handler.destroy_zones(ctx.owner, to_destroy)
	else:
		# Didn't pay full cost, destroy self
		if my_zone >= 0:
			await ctx.effect_handler.destroy_zones(ctx.owner, [my_zone])
