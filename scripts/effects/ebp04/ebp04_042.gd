extends CardEffect
# Mothra Imago (2004)
# <Enter> If 3+ rank 1 strategy cards in discard → opp rage -1.


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.rage > 0


func on_enter(ctx: EffectContext) -> void:
	var rank1_strat_count: int = 0
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.STRATEGY and card.get("rank", 0) == 1:
			rank1_strat_count += 1
	if rank1_strat_count < 3:
		return
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
