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

	if ctx.owner.main_deck.is_empty():
		return

	var card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()
	ctx.effect_handler.log_message.emit(
		GameLog.effect_milled_card(ctx.owner.player_id, ctx.card_data.get("id", ""), card.get("id", ""))
	)

	var revealed: Array[Dictionary] = [card]
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, revealed, revealed,
		"Sent to discard pile:")

	if card.get("card_type") == CardEnums.CardType.BATTLE:
		var opponent_tl: int = ctx.opponent.get_threat_level()
		if opponent_tl <= 50000 and ctx.opponent.monster_zone > 1:
			await ctx.effect_handler.retreat_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
