extends CardEffect
## EBP04-024: Godzilla Ultima - Monster Rank 4 (Green)
## <Enter> If you have 10 or more green battle cards in your discard pile,
## <Destroy> a desired number of your opponent's battle cards until their total
## Ranks equal 7 or less combined.
## For each green battle card in your discard pile this card gains 1,000 threat.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "boosts_threat"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	return _green_battle_discard_count(ctx) * 1000


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return not opponent.get_occupied_zone_indices().is_empty()


func on_enter(ctx: EffectContext) -> void:
	if _green_battle_discard_count(ctx) < 10:
		return

	# Repeatedly destroy opp battle cards until total remaining ranks <= 7
	while true:
		var total_rank: int = 0
		var opp_zones_with_cards: Array[int] = []
		var destroyable_zones: Array[int] = []
		for i in range(8):
			var zone_card := ctx.opponent.get_zone_top_card(i)
			if not zone_card.is_empty():
				total_rank += ctx.field_rank(zone_card, ctx.opponent.player_id)
				opp_zones_with_cards.append(i)
				if ctx.effect_handler.can_destroy_card(ctx.opponent, zone_card):
					destroyable_zones.append(i)

		if total_rank <= 7 or destroyable_zones.is_empty():
			break

		var chosen: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.opponent.player_id, destroyable_zones,
			tr("STR_EFF_DESTROY_OPP_REMAINING_RANKS_FMT") % 7)
		if chosen < 0:
			break
		await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])


func _green_battle_discard_count(ctx: EffectContext) -> int:
	var count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card) and CardUtils.has_color(card, CardEnums.CardColor.GREEN):
			count += 1
	return count
