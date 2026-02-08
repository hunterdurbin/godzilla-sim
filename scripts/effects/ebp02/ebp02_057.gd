extends CardEffect

## EBP02-057: SpaceGodzilla Flying Form - Monster Rank 4 (Green)
## <Enter> Move 1 of your opponent's battle cards in the same column as this card
## to an unoccupied zone.
## Whenever this card's <Rage> is increased, play 2 "Crystals" tokens.
## [TODO: Token creation (Crystals) not yet supported - rage trigger deferred]


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var opp_columns := get_opponent_column_zones(monster_zone_idx)

	# Find opponent's battle cards in same column
	var targetable: Array[int] = []
	for zi in opp_columns:
		if not ctx.opponent.is_zone_empty(zi):
			targetable.append(zi)

	if targetable.is_empty():
		return

	var source: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, targetable,
		"Choose an opponent's battle card in the same column to move:", true)
	if source < 0:
		return

	var empty := ctx.opponent.get_empty_zone_indices()
	if empty.is_empty():
		return

	var dest: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, empty,
		"Choose an unoccupied zone to move it to:")
	if dest < 0:
		return

	var stack: Array = ctx.opponent.zones[source]
	ctx.opponent.zones[source] = []
	ctx.opponent.zones[dest] = stack
	ctx.opponent.zones_changed.emit()
