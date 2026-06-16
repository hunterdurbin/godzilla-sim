extends CardEffect
# Zilla (Battle R4)
# At the beginning of your end phase, move this card to an adjacent zone horizontal to
# the zone this card currently occupies. Then, if this card is in a zone adjacent to
# your monster card, <Destroy> this card..
#
# Tested: Yes
# Known issues: None
# Edge cases: Occupied destination zone is overloaded (not destroyed)
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.END, "own_turn": true},
}


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	# "Adjacent horizontal" = same row neighbors
	# Back row: zones 1-5 (indices 0-4), front row: zones 6-8 (indices 5-7)
	var horizontal_adj: Array[int] = []
	if zone_idx <= 4:
		# Back row
		if zone_idx > 0:
			horizontal_adj.append(zone_idx - 1)
		if zone_idx < 4:
			horizontal_adj.append(zone_idx + 1)
	else:
		# Front row
		if zone_idx > 5:
			horizontal_adj.append(zone_idx - 1)
		if zone_idx < 7:
			horizontal_adj.append(zone_idx + 1)

	# Filter to non-monster zones (occupied zones are valid — overloaded on move)
	var monster_idx: int = ctx.owner.monster_zone - 1
	var valid: Array[int] = []
	for adj in horizontal_adj:
		if adj != monster_idx:
			valid.append(adj)

	if valid.is_empty():
		return

	var dest := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid,
		tr("STR_EFF_EBP03_058_PROMPT"))
	if dest < 0:
		return

	ctx.effect_handler.move_zone_stack(ctx.owner, zone_idx, dest)

	# Check if now adjacent to own monster
	if monster_idx in get_adjacent_zones(dest):
		var destroyed_stack: Array = ctx.owner.clear_zone(dest)
		EffectHandler.banish_or_discard(ctx.owner, destroyed_stack)
		ctx.owner.zones_changed.emit()
		ctx.owner.discard_changed.emit()
		await ctx.effect_handler.trigger_revenge(ctx.owner.player_id, ctx.card_data)
