extends CardEffect
# Godzilla(2000) - Monster Rank 4 (Blue)
# <Awakening4> When you successfully counter your opponent's monster card, if you have
# 5 or more monster cards in your discard pile, <Destroy> all of your opponent's
# rank 6 or lower battle cards. (Active if this is in zone 4 or beyond.)
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func on_counter_success(ctx: EffectContext) -> void:
	# Awakening4: must be in zone 4 or beyond
	if ctx.owner.monster_zone < 4:
		return
	# Need 5 or more monster cards in discard pile
	var monster_count: int = 0
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			monster_count += 1
	if monster_count < 5:
		return
	# Destroy all opponent's rank 6 or lower battle cards
	var zones_to_destroy: Array[int] = []
	for i in range(8):
		var opp_card := ctx.opponent.get_zone_top_card(i)
		if not opp_card.is_empty() and opp_card.get("rank", 0) <= 6:
			zones_to_destroy.append(i)
	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
