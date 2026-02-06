extends CardEffect

## ESD01-007: Godzilla(2023) - Monster Rank 4 (Burst III)
## <Burst3> You can play this card from rank III. If you do, send this card to your
## discard pile at the beginning of your next end phase.
## <Enter> <Destroy> all of your opponent's battle cards in the same column as this card.


func get_burst_rank() -> int:
	return 3


func on_enter(ctx: EffectContext) -> void:
	# "Same column as this card" - for a monster card, the column is the monster's zone
	var monster_zone_idx: int = ctx.owner.monster_zone - 1  # 0-indexed
	_destroy_opponent_column(ctx, monster_zone_idx)


func _destroy_opponent_column(ctx: EffectContext, zone_idx: int) -> void:
	## Destroy all opponent battle cards in the given zone and the mirrored zone.
	## Zone layout: zones 1-5 (back row), zones 6-8 (front row)
	## Column pairs: 1&6, 2&7, 3&8, 4 (solo), 5 (solo)
	var opponent := ctx.opponent
	var zones_to_check: Array[int] = [zone_idx]

	# Add paired zone in same column
	if zone_idx < 5:  # Back row zones 0-4 (zones 1-5)
		var front_pair: int = zone_idx + 5  # Maps to zones 6-8 (indices 5-7)
		if front_pair < 8:
			zones_to_check.append(front_pair)
	elif zone_idx >= 5:  # Front row zones 5-7 (zones 6-8)
		var back_pair: int = zone_idx - 5  # Maps to zones 1-3 (indices 0-2)
		zones_to_check.append(back_pair)

	var destroyed_any := false
	for zi in zones_to_check:
		if zi >= 0 and zi < 8 and not opponent.zones[zi].is_empty():
			var card: Dictionary = opponent.zones[zi]
			opponent.zones[zi] = {}
			opponent.discard_pile.append(card)
			ctx.effect_handler.trigger_revenge(opponent.player_id, card)
			destroyed_any = true

	if destroyed_any:
		opponent.zones_changed.emit()
		opponent.discard_changed.emit()
