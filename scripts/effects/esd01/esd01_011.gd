extends CardEffect

## ESD01-011: Godzilla(2023) - Battle Rank 5
## <Enter> If your monster card has 2 or more <Rage>, reduce your opponent's <Rage> by 1.
## When this card is <Destroy>, place this card on the bottom of your deck instead.


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage >= 2 and ctx.opponent.rage > 0:
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)


func on_revenge(ctx: EffectContext) -> void:
	ctx.effect_handler.return_to_deck_bottom(ctx.owner, ctx.card_data)


func on_crush(ctx: EffectContext) -> void:
	ctx.effect_handler.return_to_deck_bottom(ctx.owner, ctx.card_data)
