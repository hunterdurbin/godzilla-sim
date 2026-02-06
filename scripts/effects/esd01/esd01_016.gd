extends CardEffect

## ESD01-016: Heat Ray - Strategy Rank 1
## <Destroy> all of your opponent's battle cards in the same column as your monster card.
##
## NOTE: This is a strategy card with an immediate effect when played (on_enter).


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1  # 0-indexed
	_destroy_opponent_column(ctx, monster_zone_idx)


func _destroy_opponent_column(ctx: EffectContext, zone_idx: int) -> void:
	var opponent := ctx.opponent
	var zones_to_check: Array[int] = get_opponent_column_zones(zone_idx)

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
