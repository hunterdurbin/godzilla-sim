extends CardEffect
# Godzilla (2003)
# Each time you discard a battle card from hand + opp rage=0 →
# Destroy 1 opp Rank 6 or lower battle card.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_hand_card_discarded(ctx: EffectContext, discarded_card: Dictionary) -> void:
	if discarded_card.get("card_type") != CardEnums.CardType.BATTLE:
		return
	if ctx.opponent.rage != 0:
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
		"Destroy an opponent's Rank 6 or lower battle card:")
