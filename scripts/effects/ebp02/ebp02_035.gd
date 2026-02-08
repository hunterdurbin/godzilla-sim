extends CardEffect

## EBP02-035: Biollante Plant Beast Form - Battle Rank 7 (Blue)
## <Enter> If you have 2 or more cards with <Biollante> in your discard pile, return all
## cards in your opponent's discard pile to their deck then shuffle.
## <Enter> Play 2 "Tentacles" tokens in zones adjacent to this card.
## [TODO: Token creation not yet supported - Tentacles tokens deferred]


func on_enter(ctx: EffectContext) -> void:
	# Count Biollante cards in discard
	var bio_count: int = 0
	for card in ctx.owner.discard_pile:
		var traits: Array = card.get("traits", [])
		if CardEnums.CardTrait.BIOLLANTE in traits:
			bio_count += 1

	if bio_count >= 2:
		# Return all opponent discard to deck and shuffle
		if not ctx.opponent.discard_pile.is_empty():
			ctx.opponent.main_deck.append_array(ctx.opponent.discard_pile)
			ctx.opponent.discard_pile.clear()
			ctx.opponent.main_deck.shuffle()
			ctx.opponent.deck_changed.emit()
			ctx.opponent.discard_changed.emit()
