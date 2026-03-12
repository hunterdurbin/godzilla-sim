extends CardEffect
# All-Weapon Attack (Strategy R4)
# Reveal top 3 of deck, send to discard.
# Destroy all opponent battle cards in zones whose numbers match the revealed ranks.
# If opponent monster is in a matching zone, retreat 1.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self", "destroys_zone", "retreats_opponent"]


func on_enter(ctx: EffectContext) -> void:
	var revealed: Array[Dictionary] = []
	for _i in range(3):
		if ctx.owner.main_deck.is_empty():
			break
		revealed.append(ctx.owner.main_deck.pop_front())

	if revealed.is_empty():
		ctx.owner.deck_changed.emit()
		return

	ctx.owner.deck_changed.emit()

	# Show revealed cards to the player
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, revealed, revealed,
		"Revealed from deck (select any to confirm):")

	# Send all revealed to discard
	var matching_ranks: Array[int] = []
	for card in revealed:
		ctx.owner.discard_pile.append(card)
		var rank: int = card.get("rank", 0)
		if rank >= 1 and rank <= 8 and rank not in matching_ranks:
			matching_ranks.append(rank)
	ctx.owner.discard_changed.emit()

	# Destroy opponent battle cards in zones matching revealed ranks
	# rank N = zone N = index N-1
	var zones_to_destroy: Array[int] = []
	for rank in matching_ranks:
		var zone_idx: int = rank - 1
		if ctx.opponent.zone_has_cards(zone_idx):
			zones_to_destroy.append(zone_idx)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)

	# If opponent monster is in a matching zone, retreat 1
	if ctx.opponent.monster_zone in matching_ranks and ctx.opponent.monster_zone > 1:
		await ctx.effect_handler.retreat_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
