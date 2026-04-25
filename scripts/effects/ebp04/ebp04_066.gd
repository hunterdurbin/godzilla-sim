extends CardEffect
## EBP04-066: Gigan (2004) - Battle Rank 7 (Green)
## <Opponent's Turn> If there is a Battle card in your zones that is not green,
## all strategy cards in your opponent's hand gain +2 in rank (after play they
## return to their original rank).
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_strategy_hand_rank_modifier(ctx: EffectContext, _card: Dictionary, target_player_id: int) -> int:
	if ctx.is_owner(target_player_id):
		return 0
	if ctx.game_state.current_player_id != target_player_id:
		return 0
	var has_non_green_battle: bool = ctx.owner.has_zone_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and not CardUtils.has_color(c, CardEnums.CardColor.GREEN))
	return 2 if has_non_green_battle else 0
