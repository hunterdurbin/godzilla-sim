extends CardEffect
# Godzilla (2004)
# <Burst II>
# <Enter> If you have a Rank 1 strategy card in play, Destroy one of your opponent's
# Rank 6 or lower battle cards.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_burst_rank() -> int:
	return 2


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return not opponent.get_all_zone_cards().is_empty()


func on_enter(ctx: EffectContext) -> void:
	if not _has_rank1_strategy(ctx):
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
		"Destroy an opponent's Rank 6 or lower battle card:")


func _has_rank1_strategy(ctx: EffectContext) -> bool:
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("rank", 99) == 1:
			return true
	return false
