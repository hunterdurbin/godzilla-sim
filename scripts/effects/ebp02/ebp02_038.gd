extends CardEffect

## EBP02-038: Godzilla 2000: Millennium - Strategy Rank 2 (Blue)
## Choose one of the following:
## - <Destroy> 1 of your opponent's rank 5 or lower battle cards.
## - If you have 10 or more monster cards in your discard pile,
##   <Destroy> 1 of your opponent's battle cards in zone 8.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var options: Array[String] = []
	var option_ids: Array[int] = []

	# Option 0: Destroy 1 rank 5 or lower (if targets exist)
	var has_r5_targets: bool = false
	for i in range(8):
		var top := ctx.opponent.get_zone_top_card(i)
		if not top.is_empty() and top.get("rank", 0) <= 5:
			has_r5_targets = true
			break
	if has_r5_targets:
		options.append("Destroy 1 of opponent's rank 5 or lower battle cards")
		option_ids.append(0)

	# Option 1: Destroy zone 8 card (requires 10+ monster cards in discard)
	var monster_count: int = 0
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			monster_count += 1
	if monster_count >= 10:
		var opp_z8 := ctx.opponent.get_zone_top_card(7)
		if not opp_z8.is_empty():
			options.append("Destroy opponent's battle card in zone 8")
			option_ids.append(1)

	if options.is_empty():
		return

	var chosen_id: int
	if options.size() == 1:
		chosen_id = option_ids[0]
	else:
		var chosen_idx: int = await ctx.effect_handler.select_choice(
			ctx.owner.player_id, options, "Choose one:")
		if chosen_idx < 0 or chosen_idx >= option_ids.size():
			chosen_id = option_ids[0]
		else:
			chosen_id = option_ids[chosen_idx]

	match chosen_id:
		0:
			await ctx.effect_handler.destroy_zone_target(
				ctx.owner.player_id, ctx.opponent,
				func(card: Dictionary) -> bool: return card.get("rank", 0) <= 5,
				"Choose an opponent's rank 5 or lower battle card to destroy:")
		1:
			await ctx.effect_handler.destroy_zones(ctx.opponent, [7])
