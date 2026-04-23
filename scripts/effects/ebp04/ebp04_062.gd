extends CardEffect
## EBP04-062: Anguirus (2021) - Battle Rank 5 (Green)
## <Revenge> If you have 10 or more green battle cards in your discard pile,
## increase your monster card's <Rage> for each of your opponent's battle cards
## in the same column as your monster card.
##
## Tested: No
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
		if (card.get("card_type") == CardEnums.CardType.BATTLE and
				CardEnums.CardColor.GREEN in card.get("colors", [])):
			green_count += 1
	if green_count < 10:
		return

	var monster_idx: int = ctx.owner.monster_zone - 1
	var col_zones := get_opponent_column_zones(monster_idx)
	var opp_count: int = 0
	for zi in col_zones:
		if ctx.opponent.zone_has_cards(zi):
			opp_count += 1

	if opp_count == 0:
		return

	var old_rage := ctx.owner.rage
	ctx.owner.rage += opp_count
	ctx.owner.rage_changed.emit(ctx.owner.rage)
	await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
