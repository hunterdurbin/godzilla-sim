extends CardEffect

## EBP01-072: Gigan(2022) - Battle Rank 6 (White)
## <Enter> If this card is in the same column as your opponent's monster card, send the
## top card of your deck to your discard pile. If it is a battle card, move your opponent's
## monster card with 50,000 or lower threat level backward by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "mill_self", "column_dependent_monster"]


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var opp_columns := get_opponent_column_zones(zone_idx)
	if (ctx.opponent.monster_zone - 1) not in opp_columns:
		return

	var card := await ctx.mill_one()
	if card.is_empty():
		return

	if CardUtils.is_battle(card):
		var opponent_tl: int = ctx.effect_handler.get_effective_threat_level(ctx.opponent.player_id)
		if opponent_tl <= 50000 and ctx.opponent.monster_zone > 1:
			await ctx.effect_handler.retreat_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
