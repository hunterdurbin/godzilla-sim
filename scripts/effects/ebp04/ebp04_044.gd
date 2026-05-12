extends CardEffect
## EBP04-044: Hedorah(2004) - Battle Rank 8 (Red)
## <Awakening 4> You can play this card from your hand with its rank reduced by 2 for
## each non-red battle card in your zones. (Active if your monster card is in zone 4 or
## beyond. After being played, this card is rank 8.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["zone_dependent"]


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	if not ctx.is_awakening(4):
		return 0
	var non_red_count: int = ctx.owner.count_zones_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and not CardUtils.has_color(c, CardEnums.CardColor.RED))
	return -2 * non_red_count
