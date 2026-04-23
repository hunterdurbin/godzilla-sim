extends CardEffect
## EBP04-002: Godzilla (2004) - Monster Rank 2 (Red)
## Each time you <Destroy> an opponent's battle card in the same column as this
## card, if you have a Rank 1 strategy card in play, your opponent discards until
## they have 2 cards in hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "column_dependent_monster_self"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_opponent_zone_card_destroyed(ctx: EffectContext, _destroyed_card: Dictionary, zone_idx: int) -> void:
	var my_zone_idx: int = ctx.owner.monster_zone - 1
	if my_zone_idx < 0:
		return
	if zone_idx not in get_opponent_column_zones(my_zone_idx):
		return
	var has_rank1_strategy := false
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty() and ctx.field_rank(sz, ctx.owner.player_id) == 1:
			has_rank1_strategy = true
			break
	if not has_rank1_strategy:
		return
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 2)
