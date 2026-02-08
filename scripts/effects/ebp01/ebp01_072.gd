extends CardEffect

## EBP01-072: Gigan(2022) - Battle Rank 6 (White)
## <Enter> If this card is in the same column as your opponent's monster card, send the
## top card of your deck to your discard pile. If it is a battle card, move your opponent's
## monster card with 50,000 or lower threat level backward by 1 zone.


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := _find_zone_of_card(ctx)
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

	if card.get("card_type") == CardEnums.CardType.BATTLE:
		var opponent_tl: int = ctx.opponent.get_threat_level()
		if opponent_tl <= 50000 and ctx.opponent.monster_zone > 1:
			ctx.opponent.monster_zone -= 1
			ctx.opponent.monster_changed.emit()


func _find_zone_of_card(ctx: EffectContext) -> int:
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == card_id:
			return i
	return -1
