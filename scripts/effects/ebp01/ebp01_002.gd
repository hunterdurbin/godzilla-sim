extends CardEffect

## EBP01-002: Godzilla(1954) - Monster Rank 2 (Burst I)
## <Burst1> <When Invading> Send the top card of your deck to your discard pile.
## If it is a monster card, <Destroy> 1 of your opponent's rank 5 or lower battle cards.


func get_burst_rank() -> int:
	return 1


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if ctx.owner.main_deck.is_empty():
		return

	var card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	if card.get("card_type") == CardEnums.CardType.MONSTER:
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(c: Dictionary) -> bool: return c.get("rank", 0) <= 5,
			"Choose an opponent's rank 5 or lower battle card to destroy:")
