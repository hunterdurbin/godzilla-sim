extends CardEffect
## EBP04-022: Godzilla Amphibia - Monster Rank 2 (Green)
## When this card is successfully countered, reveal 5 cards from the top of
## your deck. For each green battle card revealed, <Destroy> 1 6000 or less
## counter power battle card in your opponent's areas 1-5.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_counter_success(ctx: EffectContext) -> void:
	var revealed := await ctx.effect_handler.reveal_deck_top(ctx.owner.player_id, 5)
	if revealed.is_empty():
		return
	ctx.effect_handler.discard_cards(ctx.owner.player_id, revealed)

	var green_count: int = 0
	for card in revealed:
		if CardUtils.is_battle(card) and CardUtils.has_color(card, CardEnums.CardColor.GREEN):
			green_count += 1

	# Collect valid target zones (zones 1-5 = indices 0-4 with <= 6000 CP)
	for i in range(green_count):
		var valid_zones: Array[int] = []
		for zi in range(5):
			var opp_card := ctx.opponent.get_zone_top_card(zi)
			if not opp_card.is_empty() and opp_card.get("counter_power", 0) <= 6000:
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
