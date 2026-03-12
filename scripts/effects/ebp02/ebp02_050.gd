extends CardEffect

## EBP02-050: Mecha-King Ghidorah - Monster Rank 4 (Green)
## <Enter> If there are 5 or more cards under this card, choose one of the following:
## - <Destroy> 3 of your opponent's rank 6 or lower battle cards.
## - Your opponent discards cards until they have 2 cards remaining in their hand.
## - Increase this card's <Rage> by 3.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "disrupts_hand", "boosts_threat"]


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_stack.size() < 5:
		return

	# Build available options
	var options: Array[String] = []
	var option_ids: Array[int] = []

	# Option 0: Destroy 3 R6- battle cards
	var has_r6_targets: bool = false
	for i in range(8):
		var top := ctx.opponent.get_zone_top_card(i)
		if not top.is_empty() and ctx.field_rank(top, ctx.opponent.player_id) <= 6:
			has_r6_targets = true
			break
	if has_r6_targets:
		options.append("Destroy 3 of opponent's rank 6 or lower battle cards")
		option_ids.append(0)

	# Option 1: Opponent discards to 2
	if ctx.opponent.hand.size() > 2:
		options.append("Opponent discards to 2 cards in hand")
		option_ids.append(1)

	# Option 2: +3 rage (always available)
	options.append("Increase Rage by 3")
	option_ids.append(2)

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
					func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
					"Choose a rank 6 or lower battle card to destroy:")
		1:
			await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 2)
		2:
			var old_rage: int = ctx.owner.rage
			ctx.owner.rage += 3
			ctx.owner.rage_changed.emit(ctx.owner.rage)
			await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
