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
	var revealed := await ctx.effect_handler.reveal_deck_top(ctx.owner.player_id, 3)
	if revealed.is_empty():
		return
	ctx.effect_handler.discard_cards(ctx.owner.player_id, revealed)

	var matching_ranks: Array[int] = []
	for card in revealed:
		var rank: int = card.get("rank", 0)
		if rank >= 1 and rank <= 8 and rank not in matching_ranks:
			matching_ranks.append(rank)

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
