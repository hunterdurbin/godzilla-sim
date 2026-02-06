extends CardEffect

## ESD01-006: Godzilla(2023) - Monster Rank 3 (Burst II)
## <Burst2> You can play this card from rank II. If you do, send this card to your
## discard pile at the beginning of your next end phase.
## <Enter> <Destroy> 1 of your opponent's rank 4 or lower battle cards.


func get_burst_rank() -> int:
	return 2


func on_enter(ctx: EffectContext) -> void:
	# Destroy 1 of opponent's rank 4 or lower battle cards
	var opponent := ctx.opponent
	for i in range(8):
		var zone_card: Dictionary = opponent.zones[i]
		if not zone_card.is_empty() and zone_card.get("rank", 0) <= 4:
			opponent.zones[i] = {}
			opponent.discard_pile.append(zone_card)
			opponent.zones_changed.emit()
			opponent.discard_changed.emit()
			# Trigger revenge on the destroyed card
			ctx.effect_handler.trigger_revenge(opponent.player_id, zone_card)
			return
