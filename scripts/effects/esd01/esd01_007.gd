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
	var column_zones := get_opponent_column_zones(monster_zone_idx)
	ctx.effect_handler.destroy_zones(ctx.opponent, column_zones)
