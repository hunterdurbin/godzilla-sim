extends CardEffect

## ESD01-002: Godzilla(2023) - Monster Rank 2
## <When Invading> Search your deck for up to 1 rank III card named Godzilla(2023)
## with <Burst>, reveal it, add it to your hand, then shuffle your deck.
## (If you invaded 2 zones, activate this effect 2 times)


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	_search_for_burst_godzilla(ctx)


func _search_for_burst_godzilla(ctx: EffectContext) -> void:
	var player := ctx.owner
	# Search deck for a rank 3 Godzilla(2023) monster with Burst
	for i in range(player.main_deck.size()):
		var card: Dictionary = player.main_deck[i]
		if card.get("name", "") == "Godzilla(2023)" \
				and card.get("rank", 0) == 3 \
				and card.get("card_type") == CardEnums.CardType.MONSTER:
			# Check if it has Burst by checking the effect script
			var effect := ctx.effect_handler.get_effect(card)
			if effect and effect.get_burst_rank() >= 0:
				player.main_deck.remove_at(i)
				player.hand.append(card)
				player.main_deck.shuffle()
				player.hand_changed.emit()
				player.deck_changed.emit()
				return
