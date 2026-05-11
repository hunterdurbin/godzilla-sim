extends CardEffect
## EBP04-022: Godzilla Amphibia - Monster Rank 2 (Green)
## When this card is countered, reveal the top 5 cards of your deck and send them to
## your discard pile. For each green battle card revealed this way, <Destroy> 1 of your
## opponent’s battle cards with 6000 or lower counter power in zones 1–5.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_self_countered(ctx: EffectContext) -> void:
	var revealed := await ctx.mill(5)
	if revealed.is_empty():
		return

	var green_count: int = 0
	for card in revealed:
		if CardUtils.is_battle(card) and CardUtils.has_color(card, CardEnums.CardColor.GREEN):
			green_count += 1

	# Collect valid target zones (areas 1-5 = indices 0-4 with effective CP <= 6000).
	# Effective CP is recomputed each iteration since destroying a card can shift
	# modifiers granted to its neighbors via get_field_cp_modifiers.
	for i in range(green_count):
		var valid_zones: Array[int] = []
		for zi in ctx.effect_handler.get_zones_in_cp_range(ctx.opponent.player_id, -1, 6000):
			if zi < 5:
				valid_zones.append(zi)
		if valid_zones.is_empty():
			break
		var remaining: int = green_count - i
		var chosen: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.opponent.player_id, valid_zones,
			tr("STR_EFF_DESTROY_OPP_CP_LEQ_FMT") % remaining)
		if chosen < 0:
			break
		await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
