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
	var opponent := ctx.opponent
	var zones_to_check: Array[int] = get_opponent_column_zones(zone_idx)

	var destroyed_any := false
	for zi in zones_to_check:
		if zi >= 0 and zi < 8 and not opponent.is_zone_empty(zi):
			var top_card := opponent.get_zone_top_card(zi)
			var stack: Array = opponent.clear_zone(zi)
			opponent.discard_pile.append_array(stack)
			ctx.effect_handler.trigger_revenge(opponent.player_id, top_card)
			destroyed_any = true

	if destroyed_any:
		opponent.zones_changed.emit()
		opponent.discard_changed.emit()
