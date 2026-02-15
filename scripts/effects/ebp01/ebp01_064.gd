extends CardEffect

## EBP01-064: Godzilla vs. Megaguirus - Strategy Rank 5 (Blue)
## Choose one of the following:
## - <Destroy> 1 of your opponent's rank 4 or lower battle cards.
## - If you have 4 or more battle cards in your zones, choose 1 of your opponent's
##   zones and <Destroy> all battle cards in that zone and zones adjacent to it.
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

	# Option 0: Destroy 1 rank 4 or lower (always available if targets exist)
	var has_r4_targets: bool = false
	for i in range(8):
		var top := ctx.opponent.get_zone_top_card(i)
		if not top.is_empty() and top.get("rank", 0) <= 4:
			has_r4_targets = true
			break
	if has_r4_targets:
		options.append("Destroy 1 of opponent's rank 4 or lower battle cards")
		option_ids.append(0)

	# Option 1: Destroy zone + adjacent (requires 4+ own battle cards)
	var battle_count: int = 0
	for i in range(8):
		if ctx.owner.zone_has_cards(i):
			battle_count += 1
	if battle_count >= 4:
		var has_opp_cards: bool = false
		for i in range(8):
			if ctx.opponent.zone_has_cards(i):
				has_opp_cards = true
				break
		if has_opp_cards:
			options.append("Choose a zone and destroy all cards there and in adjacent zones")
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
				func(card: Dictionary) -> bool: return card.get("rank", 0) <= 4,
				"Choose an opponent's rank 4 or lower battle card to destroy:")
		1:
			var targetable_zones: Array[int] = []
			for i in range(8):
				if ctx.opponent.zone_has_cards(i):
					targetable_zones.append(i)
			var chosen_zone: int = await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.opponent.player_id, targetable_zones,
				"Choose a zone — all cards there and in adjacent zones will be destroyed:")
			if chosen_zone >= 0:
				var affected_zones: Array[int] = [chosen_zone]
				for adj in get_adjacent_zones(chosen_zone):
					if adj not in affected_zones:
						affected_zones.append(adj)
				var zones_to_destroy: Array[int] = []
				for zi in affected_zones:
					if ctx.opponent.zone_has_cards(zi):
						zones_to_destroy.append(zi)
				if not zones_to_destroy.is_empty():
					await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
