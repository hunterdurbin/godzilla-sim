extends CardEffect
# Godzilla(2000) - Monster Rank 4 (Blue)
# <Awakening4> When you successfully counter your opponent’s monster card, if you have
# 5 or more monster cards in your discard pile, <Destroy> all of your opponent’s rank 6
# or lower battle cards. (Active if this card is in zone 4 or beyond.)
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func bot_can_fulfill_counter_success(owner: PlayerState, _opponent: PlayerState) -> bool:
	if not owner.is_awakening(4):
		return false
	var monster_count := 0
	for card in owner.discard_pile:
		if CardUtils.is_monster(card):
			monster_count += 1
			if monster_count >= 5:
				return true
	return false


func on_counter_success(ctx: EffectContext) -> void:
	# Awakening4: must be in zone 4 or beyond
	if not ctx.is_awakening(4):
		return
	# Need 5 or more monster cards in discard pile
	var monster_count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_monster(card):
			monster_count += 1
	if monster_count < 5:
		return
	# Destroy all opponent's rank 6 or lower battle cards
	var zones_to_destroy: Array[int] = ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 6)
	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
