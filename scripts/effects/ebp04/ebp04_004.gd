extends CardEffect
## EBP04-004: Godzilla (2004) - Monster Rank 3 (Red)
## <Enter> If you have a rank 1 strategy card in play, increase this card’s <Rage> by 2.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func on_enter(ctx: EffectContext) -> void:
	if not _has_rank1_strategy(ctx):
		return
	await ctx.effect_handler.gain_rage(ctx.owner.player_id, 2, ctx.card_data.get("id", ""))


func _has_rank1_strategy(ctx: EffectContext) -> bool:
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("rank", 99) == 1:
			return true
	return false
