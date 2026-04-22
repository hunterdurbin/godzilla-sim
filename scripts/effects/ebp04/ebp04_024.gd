extends CardEffect
# Godzilla Ultima
# <Enter> If 10+ green battle cards in discard, Destroy opp cards until total rank <= 7.
# Continuous: per green battle card in discard → +1000 threat.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "boosts_threat"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	return _green_battle_discard_count(ctx) * 1000


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return not opponent.get_all_zone_cards().is_empty()


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
			"Destroy an opponent's battle card (total remaining ranks must reach 7 or less):")
		if chosen < 0:
			break
		await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])


func _green_battle_discard_count(ctx: EffectContext) -> int:
	var count: int = 0
	for card in ctx.owner.discard_pile:
		if (card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardColor.GREEN in card.get("colors", [])):
			count += 1
	return count
