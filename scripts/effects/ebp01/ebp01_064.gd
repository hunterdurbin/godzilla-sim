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


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_enter(ctx: EffectContext) -> void:
	var options: Array[String] = []
	var option_ids: Array[int] = []

	# Option 0: Destroy 1 rank 4 or lower (always available if targets exist)
	var has_r4_targets: bool = not ctx.effect_handler.get_zones_in_rank_range(
		ctx.opponent.player_id, -1, 4).is_empty()
	if has_r4_targets:
		options.append("Destroy 1 of opponent's rank 4 or lower battle cards")
		option_ids.append(0)

	# Option 1: Destroy zone + adjacent (requires 4+ own battle cards)
	if ctx.owner.get_battle_card_zone_indices().size() >= 4:
		var has_opp_cards: bool = not ctx.opponent.get_battle_card_zone_indices().is_empty()
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
			ctx.owner.player_id, options, tr("STR_EFF_CHOOSE_ONE"))
		if chosen_idx < 0 or chosen_idx >= option_ids.size():
			chosen_id = option_ids[0]
		else:
			chosen_id = option_ids[chosen_idx]

	match chosen_id:
		0:
			await ctx.effect_handler.destroy_zone_target(
				ctx.owner.player_id, ctx.opponent,
				func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 4,
				tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 4)
		1:
			var all_zones: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
			await ctx.effect_handler.destroy_zone_and_adjacent(
				ctx.owner.player_id, ctx.opponent, all_zones,
				tr("STR_EFF_EBP01_064_PROMPT"))
