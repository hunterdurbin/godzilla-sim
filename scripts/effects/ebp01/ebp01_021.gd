extends CardEffect

## EBP01-021: Rodan(1968) - Battle Rank 4
## <Enter> If this card is in the same column as your opponent's monster card, look at
## the top 2 cards of your deck, put any number on top of your deck in any order,
## and send the rest to your discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["column_dependent_monster"]


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var opp_columns := get_opponent_column_zones(zone_idx)
	if (ctx.opponent.monster_zone - 1) not in opp_columns:
		return

	await ctx.effect_handler.arrange_deck_top(
		ctx.owner.player_id, 2, tr("STR_EFF_DECK_ARRANGE_TOP"))
