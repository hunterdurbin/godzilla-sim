extends CardEffect

## EBP01-003: Godzilla(1954) - Monster Rank 3
## Whenever this card's <Rage> is increased, send the top card of your deck to your
## discard pile. If it is a monster card, <Destroy> 1 of your opponent's rank 6 or lower
## battle cards.


func on_rage_changed(ctx: EffectContext, old_rage: int, new_rage: int) -> void:
	if new_rage <= old_rage:
		return
	if ctx.owner.main_deck.is_empty():
		return

	var card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	if card.get("card_type") == CardEnums.CardType.MONSTER:
		await ctx.effect_handler.destroy_zone_target(
			ctx.owner.player_id, ctx.opponent,
			func(c: Dictionary) -> bool: return c.get("rank", 0) <= 6,
			"Choose an opponent's rank 6 or lower battle card to destroy:")
