extends CardEffect

## EBP03-016: Godzilla(2003) - Monster Rank 3 (Blue)
## Whenever you discard a battle card from your hand, reduce your opponent's Rage by 1.
## If your opponent's Rage is 0, increase this card's Rage by 1 instead.


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_hand_card_discarded(ctx: EffectContext, discarded_card: Dictionary) -> void:
	if discarded_card.get("card_type") != CardEnums.CardType.BATTLE:
		return
	if ctx.opponent.rage > 0:
		var old_rage: int = ctx.opponent.rage
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)
	else:
		var old_rage: int = ctx.owner.rage
		ctx.owner.rage += 1
		ctx.owner.rage_changed.emit(ctx.owner.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
