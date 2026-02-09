extends CardEffect
# All-Weapon Attack (Strategy R4)
# Reveal top 3 of deck, send to discard.
# Destroy all opponent battle cards in zones whose numbers match the revealed ranks.
# If opponent monster is in a matching zone, retreat 1.


func on_enter(ctx: EffectContext) -> void:
	var revealed: Array[Dictionary] = []
	for _i in range(3):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())

	if revealed.is_empty():
		ctx.owner.deck_changed.emit()
		return

	# Send all revealed to discard
	var matching_ranks: Array[int] = []
	for card in revealed:
		ctx.owner.discard_pile.append(card)
		var rank: int = card.get("rank", 0)
		if rank >= 1 and rank <= 8 and rank not in matching_ranks:
			matching_ranks.append(rank)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	# Destroy opponent battle cards in zones matching revealed ranks
	# rank N = zone N = index N-1
	var zones_to_destroy: Array[int] = []
	for rank in matching_ranks:
		var zone_idx: int = rank - 1
		if not ctx.opponent.is_zone_empty(zone_idx):
			zones_to_destroy.append(zone_idx)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)

	# If opponent monster is in a matching zone, retreat 1
	if ctx.opponent.monster_zone in matching_ranks and ctx.opponent.monster_zone > 1:
		var old_zone := ctx.opponent.monster_zone
		ctx.opponent.monster_zone -= 1
		ctx.opponent.monster_changed.emit()
		await ctx.effect_handler.trigger_monster_advance(ctx.opponent.player_id, old_zone, ctx.opponent.monster_zone)
