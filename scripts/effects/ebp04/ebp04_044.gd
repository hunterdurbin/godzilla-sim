extends CardEffect
## EBP04-044: Hedorah (2004) - Battle Rank 8 (Red)
## <Awakening 4> For each non-red battle card in your zones, you can play this
## from your hand at -2 rank.
##
## Tested: No
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
	if ctx.owner.monster_zone < 4:
		return 0
	var non_red_count: int = 0
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty() or zone_card.get("card_type") != CardEnums.CardType.BATTLE:
			continue
		var colors: Array = zone_card.get("colors", [])
		if CardEnums.CardColor.RED not in colors:
			non_red_count += 1
	return -2 * non_red_count
