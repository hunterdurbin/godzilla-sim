extends CardEffect
# Godzilla (2000)
# <Enter> If 5+ monster cards in discard, reveal + discard top 3 of deck.
# For each revealed rank, Destroy opp battle cards in same zone number
# OR retreat opp monster backward 1 zone.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "retreats_opponent"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	var monster_count: int = 0
	for card in owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			monster_count += 1
	return monster_count >= 5


func on_enter(ctx: EffectContext) -> void:
	var monster_count: int = 0
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			monster_count += 1
	if monster_count < 5:
		return

	# Reveal top 3 cards
	var revealed: Array[Dictionary] = []
	for i in range(3):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())

	if revealed.is_empty():
		return

	# Show revealed cards
	ctx.effect_handler.cards_revealed_requested.emit(
		ctx.owner.player_id, revealed, "Revealed cards from deck top:")
	await ctx.effect_handler._cards_revealed_resolved

	# Discard all revealed
	for card in revealed:
		ctx.owner.discard_pile.append(card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	# Collect unique ranks
	var ranks: Array[int] = []
	for card in revealed:
		var r: int = card.get("rank", 0)
		if r > 0 and r not in ranks:
			ranks.append(r)

	# For each rank, offer: destroy opp battle in zone N OR retreat opp monster
	for rank in ranks:
		var zone_idx: int = rank - 1  # rank 1 = zone 1 = index 0
		if zone_idx < 0 or zone_idx > 7:
			continue

		var opp_card_in_zone := ctx.opponent.get_zone_top_card(zone_idx)
		var opp_monster_zone_matches := ctx.opponent.monster_zone == rank

		if opp_card_in_zone.is_empty() and not opp_monster_zone_matches:
			continue

		var options: Array[String] = []
		if not opp_card_in_zone.is_empty():
			options.append("Destroy opponent's battle card in zone %d" % rank)
		if opp_monster_zone_matches and ctx.opponent.monster_zone > 1:
			options.append("Retreat opponent's monster 1 zone")
		options.append("Skip")

		if options.size() <= 1:
			continue

		var chosen: int = await ctx.effect_handler.select_choice(
			ctx.owner.player_id, options,
			"Revealed Rank %d — choose an effect:" % rank)

		if chosen < 0:
			continue

		var chosen_label: String = options[chosen]
		if "Destroy" in chosen_label and not opp_card_in_zone.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, [zone_idx])
		elif "Retreat" in chosen_label and opp_monster_zone_matches:
			await ctx.effect_handler.retreat_monster_to_zone(
				ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
