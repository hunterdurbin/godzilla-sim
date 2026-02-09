extends CardEffect

## EBP02-028: Biollante Plant Beast Form - Monster Rank 4 (Blue)
## <Enter> Play as many rank 4 or lower battle cards with <Evolution> from your
## discard pile to each of this card's adjacent zones. (You must play as many as
## possible and you may play the battle cards in zones already occupied by other
## battle cards. Maximum of 3 cards.)


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	if monster_zone_idx < 0:
		return

	var adjacent := get_adjacent_zones(monster_zone_idx)
	if adjacent.is_empty():
		return

	# Collect rank 4 or lower battle cards with Evolution from discard pile
	var matching: Array[Dictionary] = []
	for card in ctx.owner.discard_pile:
		if card.get("card_type") != CardEnums.CardType.BATTLE:
			continue
		if card.get("rank", 99) > 4:
			continue
		if card.get("evolution_rank", -1) < 0:
			continue
		matching.append(card)

	if matching.is_empty():
		return

	# Play as many as possible to adjacent zones (max 3)
	var placed: int = 0
	for zi in adjacent:
		if placed >= 3 or matching.is_empty():
			break

		var card: Dictionary = matching.pop_front()

		# Remove card from discard pile
		var card_id: String = card.get("id", "")
		for i in range(ctx.owner.discard_pile.size() - 1, -1, -1):
			if ctx.owner.discard_pile[i].get("id", "") == card_id:
				ctx.owner.discard_pile.remove_at(i)
				break

		# Handle overload: destroy existing card in zone if occupied
		if not ctx.owner.is_zone_empty(zi):
			var destroyed_stack: Array = ctx.owner.clear_zone(zi)
			var top_card: Dictionary = destroyed_stack[0]
			EffectHandler.banish_or_discard(ctx.owner, destroyed_stack)
			await ctx.effect_handler.trigger_revenge(ctx.owner.player_id, top_card)

		ctx.owner.push_zone_card(zi, card)
		placed += 1
		await ctx.effect_handler.trigger_enter(ctx.owner.player_id, card)

	if placed > 0:
		ctx.owner.zones_changed.emit()
		ctx.owner.discard_changed.emit()
