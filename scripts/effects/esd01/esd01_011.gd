extends CardEffect

## ESD01-011: Godzilla(2023) - Battle Rank 5
## <Enter> If your monster card has 2 or more <Rage>, reduce your opponent's <Rage> by 1.
## When this card is <Destroy>, place this card on the bottom of your deck instead.


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage >= 2 and ctx.opponent.rage > 0:
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)


func on_revenge(ctx: EffectContext) -> void:
	_return_to_deck_bottom(ctx)


func on_crush(ctx: EffectContext) -> void:
	_return_to_deck_bottom(ctx)


func _return_to_deck_bottom(ctx: EffectContext) -> void:
	## Instead of going to discard, move this card to the bottom of the deck.
	## The card has already been placed in discard by the game logic, so we need to
	## remove it from discard and put it at the bottom of the deck.
	var player := ctx.owner
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(player.discard_pile.size() - 1, -1, -1):
		if player.discard_pile[i].get("id", "") == card_id:
			var card: Dictionary = player.discard_pile.pop_at(i)
			player.main_deck.append(card)
			player.deck_changed.emit()
			player.discard_changed.emit()
			return
