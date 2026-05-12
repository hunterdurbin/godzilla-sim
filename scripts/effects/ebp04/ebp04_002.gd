extends CardEffect
## EBP04-002: Godzilla(2004) - Monster Rank 2 (Red)
## Whenever an opponent’s battle card in the same column as this card is <Destroy>, if
## you have a rank 1 strategy card in play, your opponent discards cards until they have
## 2 cards remaining in their hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_opponent_zone_card_destroyed": {"column": "monster"},
}


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "column_dependent_monster_self"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_opponent_zone_card_destroyed(ctx: EffectContext, _destroyed_card: Dictionary, _zone_idx: int) -> void:
	var has_rank1_strategy := false
	for sz in ctx.owner.strategy_zones:
		if not sz.is_empty() and ctx.field_rank(sz, ctx.owner.player_id) == 1:
			has_rank1_strategy = true
			break
	if not has_rank1_strategy:
		return
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 2)
