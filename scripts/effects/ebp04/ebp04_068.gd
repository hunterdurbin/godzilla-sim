extends CardEffect
## EBP04-068: Kaiser Ghidorah - Battle Rank 8 (Green)
## <Your Turn> If you have no strategy cards in play, decrease the ranks of
## strategy cards in your hand by -1 for each color of battle card in your
## discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"get_strategy_hand_rank_modifier": {"own_turn": true, "target_is_owner": true},
}


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_strategy_hand_rank_modifier(ctx: EffectContext, card: Dictionary, _target_player_id: int) -> int:
	# Turn ownership and target-hand-owner guards live in TRIGGER_FILTERS.
	if not CardUtils.is_strategy(card):
		return 0
	if ctx.owner.has_any_strategy_in_play():
		return 0
	return -CardUtils.count_distinct_colors(ctx.owner.discard_pile, CardUtils.is_battle)
