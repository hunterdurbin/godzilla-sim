extends CardEffect
## EBP04-062: Anguirus (2021) - Battle Rank 5 (Green)
## <Revenge> If you have 10 or more green battle cards in your discard pile,
## increase your monster card's <Rage> for each of your opponent's battle cards
## in the same column as your monster card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func on_revenge(ctx: EffectContext) -> void:
	var green_count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card) and CardUtils.has_color(card, CardEnums.CardColor.GREEN):
			green_count += 1
	if green_count < 10:
		return

	var opp_count := ctx.get_opponent_column_zones_with_cards(ctx.owner.monster_zone - 1).size()
	if opp_count == 0:
		return
	await ctx.effect_handler.gain_rage(ctx.owner.player_id, opp_count, ctx.card_data.get("id", ""))
