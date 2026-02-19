extends CardEffect

## EBP02-049: King Ghidorah(1991) - Monster Rank 3 (Green)
## <Enter> If there are 3 or more cards under this card, choose one of the following:
## - <Destroy> 3 of your opponent's rank 5 or lower battle cards.
## - Your opponent discards cards until they have 3 cards remaining in their hand.
## - Send the top 3 cards of your deck to your discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_stack.size() < 3:
		return

	# Build available options
	var options: Array[String] = []
	var option_ids: Array[int] = []

	# Option 0: Destroy 3 R5- battle cards
	var has_r5_targets: bool = false
	for i in range(8):
		var top := ctx.opponent.get_zone_top_card(i)
		if not top.is_empty() and ctx.field_rank(top, ctx.opponent.player_id) <= 5:
			has_r5_targets = true
			break
	if has_r5_targets:
		options.append("Destroy 3 of opponent's rank 5 or lower battle cards")
		option_ids.append(0)

	# Option 1: Opponent discards to 3
	if ctx.opponent.hand.size() > 3:
		options.append("Opponent discards to 3 cards in hand")
		option_ids.append(1)

	# Option 2: Mill 3 from own deck
	if not ctx.owner.main_deck.is_empty():
		options.append("Send top 3 cards of your deck to discard")
		option_ids.append(2)

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
			for _i in range(3):
				await ctx.effect_handler.destroy_zone_target(
					ctx.owner.player_id, ctx.opponent,
					func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 5,
					"Choose a rank 5 or lower battle card to destroy:")
		1:
			await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 3)
		2:
			var milled: Array[Dictionary] = ctx.owner.mill_cards(3)
			if not milled.is_empty():
				ctx.effect_handler.log_message.emit(
					GameLog.effect_milled_cards(ctx.owner.player_id, ctx.card_data.get("id", ""), milled)
				)
				await ctx.effect_handler.select_from_cards(
					ctx.owner.player_id, milled, milled,
					"Sent to discard pile:")
