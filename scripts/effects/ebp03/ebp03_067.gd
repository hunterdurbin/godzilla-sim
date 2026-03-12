extends CardEffect

## EBP03-067: Monster X - Battle Rank 5 (White)
## <Your Turn> When this card is discarded from your hand, if there are 2 or more colors
## among battle cards in your zones, play this card and Destroy up to 1 of your opponent's
## lowest ranked battle cards.
## This card's counter power X = 3000 * number of different colors among other battle
## cards in your zones.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "destroys_zone", "boosts_cp"]


func on_discard_from_hand(ctx: EffectContext) -> void:
	# Only on your turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var color_count: int = _count_zone_colors(ctx)
	if color_count < 2:
		return

	# Play self from discard
	await ctx.effect_handler.play_from_discard(ctx.owner.player_id, ctx.card_data)

	# Destroy up to 1 of opponent's lowest ranked battle cards
	var lowest_rank: int = 99
	for i in range(8):
		var zone_card := ctx.opponent.get_zone_top_card(i)
		if not zone_card.is_empty():
			var rank: int = ctx.field_rank(zone_card, ctx.opponent.player_id)
			if rank < lowest_rank:
				lowest_rank = rank

	if lowest_rank < 99:
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) == lowest_rank,
			"Destroy an opponent's lowest ranked battle card (or skip):")


func get_counter_power_modifier(ctx: EffectContext) -> int:
	# CP = 3000 * number of different colors among OTHER battle cards in zones
	var colors: Array[int] = []
	var my_zone: int = find_zone_of_card(ctx)
	for i in range(8):
		if i == my_zone:
			continue
		var zone_card := ctx.owner.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("card_type") == CardEnums.CardType.BATTLE:
			for c: int in zone_card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return 3000 * colors.size()


func _count_zone_colors(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if not zone_card.is_empty() and zone_card.get("card_type") == CardEnums.CardType.BATTLE:
			for c: int in zone_card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size()
