extends CardEffect

## ESD01-014: Godzilla Emerges - Strategy Rank 6
## If your monster card has 2 or more <Rage>, search your deck for up to 1 battle card
## named Godzilla(2023), play it, then shuffle your deck.
##
## NOTE: This is a strategy card with an immediate effect when played (on_enter).


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.rage < 2:
		return

	var player := ctx.owner
	# Search deck for a battle card named "Godzilla(2023)"
	for i in range(player.main_deck.size()):
		var card: Dictionary = player.main_deck[i]
		if card.get("name", "") == "Godzilla(2023)" \
				and card.get("card_type") == CardEnums.CardType.BATTLE:
			# Found one — play it to an empty zone
			var empty_zones := player.get_empty_zone_indices()
			if empty_zones.is_empty():
				return
			player.main_deck.remove_at(i)
			var target_zone: int = empty_zones[0]
			player.zones[target_zone] = card
			player.main_deck.shuffle()
			player.zones_changed.emit()
			player.deck_changed.emit()
			# Trigger enter on the newly played card
			ctx.effect_handler.trigger_enter(player.player_id, card)
			return
