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


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.monster_stack.size() >= 5


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_stack.size() < 5:
		return

	# Build available options
	var options: Array[String] = []
	var option_ids: Array[int] = []

	# Option 0: Destroy 3 R6- battle cards
	var has_r6_targets: bool = not ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 6).is_empty()
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
			ctx.owner.player_id, options, tr("STR_EFF_CHOOSE_ONE"))
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
					tr("STR_EFF_DESTROY_OWN_RANK_LOWER_FMT") % 6)
		1:
			await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 2)
		2:
			await ctx.effect_handler.gain_rage(ctx.owner.player_id, 3)
