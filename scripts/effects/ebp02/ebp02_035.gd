extends CardEffect

## EBP02-035: Biollante Plant Beast Form - Battle Rank 7 (Blue)
## <Enter> If you have 2 or more cards with <《Biollante》> in your discard pile, return all
## cards in your opponent's discard pile to their deck then shuffle.
## <Enter> Play 2 “Tentacles” tokens in zones adjacent to this card. (Tokens are
## prepared separately from your main deck.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["heals_deck"]


func on_enter(ctx: EffectContext) -> void:
	# Count Biollante cards in discard
	var bio_count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.has_trait(card, CardEnums.CardTrait.BIOLLANTE):
			bio_count += 1

	if bio_count >= 2:
		# Return all opponent discard to deck and shuffle
		ctx.effect_handler.shuffle_discard_into_deck(ctx.opponent.player_id)

	# Play 2 Tentacles tokens in adjacent zones (player chooses)
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return
	var valid_adjacent := CardEffect.get_effect_play_adjacent_zones(ctx.owner, zone_idx)
	if valid_adjacent.is_empty():
		return
	var placed: int = 0
	for _i in range(2):
		var chosen: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, valid_adjacent,
			tr("STR_EFF_EBP02_035_TOKEN_FMT") % (2 - placed))
		if chosen < 0:
			break
		await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP02-T02", chosen)
		placed += 1
		# Rule 5.11.1.3: must play to different zones if possible
		valid_adjacent.erase(chosen)
