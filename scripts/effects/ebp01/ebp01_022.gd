extends CardEffect

## EBP01-022: Titanosaurus - Battle Rank 5
## <Your Turn> Whenever your monster card's <Rage> is increased, you may move 1 of your
## other battle cards in your zones to an unoccupied zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_rage_changed": {"own_turn": true, "direction": "increase"},
}


func on_rage_changed(ctx: EffectContext, _old_rage: int, _new_rage: int) -> void:
	var my_zone := find_zone_of_card(ctx)
	if my_zone < 0:
		return

	# Find other occupied zones (excluding this card's zone)
	var occupied: Array[int] = ctx.owner.get_battle_card_zone_indices()
	occupied.erase(my_zone)
	if occupied.is_empty():
		return

	var empty_zones := ctx.owner.get_empty_zone_indices()
	if empty_zones.is_empty():
		return

	ctx.effect_handler.highlight_zone_card(ctx.owner.player_id, my_zone)

	# Choose which card to move
	var source: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, occupied,
		tr("STR_EFF_MOVE_BATTLE_TO_EMPTY"), true)

	ctx.effect_handler.unhighlight_zone_card(ctx.owner.player_id, my_zone)

	if source < 0:
		return

	# Re-check empty zones
	empty_zones = ctx.owner.get_empty_zone_indices()
	if empty_zones.is_empty():
		return

	var dest: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, empty_zones,
		tr("STR_EFF_MOVE_DEST_EMPTY"))
	if dest < 0:
		return

	var stack: Array = ctx.owner.clear_zone(source)
	ctx.owner.zones[dest] = stack
	ctx.owner.zones_changed.emit()
