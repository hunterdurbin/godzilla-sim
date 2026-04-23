extends CardEffect

## EBP02-071: Godzilla vs. King Ghidorah - Strategy Rank 4 (Green)
## Choose one of the following:
## - <Destroy> 3 of your opponent's rank 4 or lower battle cards.
## - <Awakening6> <Destroy> 2 of your opponent's rank 6 or lower battle cards.
## - <Awakening8> <Destroy> 1 of your opponent's battle cards.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(owner: PlayerState, _opponent: PlayerState) -> int:
	if owner.monster_zone >= 8:
		return -1
	elif owner.monster_zone >= 6:
		return 6
	return 4


func on_enter(ctx: EffectContext) -> void:
	var options: Array[String] = []
	var option_ids: Array[int] = []

	# Option 0: Destroy 3 rank 4 or lower (if targets exist)
	var has_r4_targets: bool = not ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 4).is_empty()
	if has_r4_targets:
		options.append("Destroy 3 of opponent's rank 4 or lower battle cards")
		option_ids.append(0)

	# Option 1: Awakening6 — Destroy 2 rank 6 or lower
	if ctx.owner.monster_zone >= 6:
		var has_r6_targets: bool = not ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 6).is_empty()
		if has_r6_targets:
			options.append("Awakening6: Destroy 2 of opponent's rank 6 or lower battle cards")
			option_ids.append(1)

	# Option 2: Awakening8 — Destroy 1 any battle card
	if ctx.owner.monster_zone >= 8:
		var has_any_target: bool = not ctx.opponent.get_occupied_zone_indices().is_empty()
		if has_any_target:
			options.append("Awakening8: Destroy 1 of opponent's battle cards")
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
					func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 4,
					"Choose an opponent's rank 4 or lower battle card to destroy:")
		1:
			for _i in range(2):
				await ctx.effect_handler.destroy_zone_target(
					ctx.owner.player_id, ctx.opponent,
					func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
					"Choose an opponent's rank 6 or lower battle card to destroy:")
		2:
			await ctx.effect_handler.destroy_zone_target(
				ctx.owner.player_id, ctx.opponent,
				func(_card: Dictionary) -> bool: return true,
				"Choose an opponent's battle card to destroy:")
