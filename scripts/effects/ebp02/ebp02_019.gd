extends CardEffect

## EBP02-019: There is no danger of the creature coming ashore. - Strategy Rank 4 (Red)
## Move 1 battle card in your zones to an unoccupied zone.
## If your monster card invaded this turn, advance your monster card by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_self"]


func on_enter(ctx: EffectContext) -> void:
	# Move 1 battle card to empty zone
	var occupied: Array[int] = ctx.owner.get_occupied_zone_indices()

	if not occupied.is_empty():
		var source: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.owner.player_id, occupied,
			"Choose a battle card to move:", true)
		if source >= 0:
			var empty := ctx.owner.get_empty_zone_indices()
			if not empty.is_empty():
				var dest: int = await ctx.effect_handler.select_zone_target(
					ctx.owner.player_id, ctx.owner.player_id, empty,
					"Choose an unoccupied zone to move it to:")
				if dest >= 0:
					var stack: Array = ctx.owner.zones[source]
					ctx.owner.zones[source] = []
					ctx.owner.zones[dest] = stack
					ctx.owner.zones_changed.emit()

	# If invaded this turn, advance monster by 1
	if ctx.owner.has_invaded_this_turn and ctx.owner.monster_zone < 8:
		await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, ctx.owner.monster_zone + 1)
