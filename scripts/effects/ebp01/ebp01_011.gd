extends CardEffect

## EBP01-011: Godzilla(Fest Godzilla) - Monster Rank 1
## When this card advances into the same column as your opponent's monster card,
## advance your opponent's monster card by 1 zone.


func on_monster_advance(ctx: EffectContext, _from_zone: int, to_zone: int) -> void:
	var my_zone_idx: int = to_zone - 1
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	var opponent_columns := get_opponent_column_zones(my_zone_idx)
	if opp_monster_idx in opponent_columns:
		if ctx.opponent.monster_zone < 8:
			ctx.opponent.monster_zone += 1
			ctx.opponent.monster_changed.emit()
