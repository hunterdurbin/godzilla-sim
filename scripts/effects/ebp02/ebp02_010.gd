extends CardEffect

## EBP02-010: King Caesar(2004) - Battle Rank 2 (Red)
## <Enter> Move 1 of your other battle cards in your zones to an unoccupied zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var card_id: String = ctx.card_data.get("id", "")
	var occupied: Array[int] = ctx.owner.get_zone_top_indices_matching(
		func(c: Dictionary) -> bool: return c.get("id", "") != card_id)

	if occupied.is_empty():
		return

	var source: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, occupied,
		"Choose a battle card to move:", true)
	if source < 0:
		return

	var empty := ctx.owner.get_empty_zone_indices()
	if empty.is_empty():
		return

	var dest: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, empty,
		"Choose an unoccupied zone to move it to:")
	if dest < 0:
		return

	var stack: Array = ctx.owner.zones[source]
	ctx.owner.zones[source] = []
	ctx.owner.zones[dest] = stack
	ctx.owner.zones_changed.emit()
