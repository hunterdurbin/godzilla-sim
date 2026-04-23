extends CardEffect
## EBP04-013: Godzilla (2000) - Monster Rank 3 (Blue)
## <Enter> If you have 5 or more monster cards in your discard pile, reveal and
## discard the top 3 cards of your deck. Of the revealed cards' ranks, <Destroy>
## all of your opponent's battle cards in the same zone number or retreat your
## opponent's monster card in the same zone number backwards by 1 zone.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


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

	# Collect unique ranks from revealed cards
	var ranks: Array[int] = []
	for card in revealed:
		var r: int = card.get("rank", 0)
		if r > 0 and r not in ranks:
			ranks.append(r)

	# Determine which effects are available across all ranks
	var destroy_zones: Array[int] = []
	var can_retreat: bool = false
	for rank in ranks:
		var zone_idx: int = rank - 1
		if zone_idx < 0 or zone_idx > 7:
			continue
		if not ctx.opponent.get_zone_top_card(zone_idx).is_empty():
			destroy_zones.append(zone_idx)
		if ctx.opponent.monster_zone == rank and ctx.opponent.monster_zone > 1:
			can_retreat = true

	if destroy_zones.is_empty() and not can_retreat:
		return

	# One choice: destroy battle cards OR retreat monster
	var options: Array[String] = []
	if not destroy_zones.is_empty():
		var zone_numbers: Array = destroy_zones.map(func(z): return str(z + 1))
		options.append("Destroy opponent battle cards in\n  zones: %s" % ", ".join(zone_numbers))
	if can_retreat:
		options.append("Retreat opponent's monster 1 zone")
	var chosen: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options, "Choose an effect for revealed ranks %s:" % str(ranks))

	if chosen < 0:
		return

	if "Destroy" in options[chosen]:
		await ctx.effect_handler.destroy_zones(ctx.opponent, destroy_zones)
	elif "Retreat" in options[chosen]:
		await ctx.effect_handler.retreat_monster_to_zone(
			ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
