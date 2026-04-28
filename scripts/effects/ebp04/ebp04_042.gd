extends CardEffect
## EBP04-042: Mothra Imago (2004) - Battle Rank 7 (Red)
## <Enter> If you have 3 or more rank 1 strategy cards in your discard pile,
## decrease your opponent's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.has_rage()


func on_enter(ctx: EffectContext) -> void:
	var rank1_strat_count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_strategy(card) and card.get("rank", 0) == 1:
			rank1_strat_count += 1
	if rank1_strat_count < 3:
		return
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
