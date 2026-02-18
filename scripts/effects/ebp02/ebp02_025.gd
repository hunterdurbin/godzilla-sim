extends CardEffect

## EBP02-025: Biollante Rose Form - Monster Rank 2 (Blue)
## This card cannot advance nor invade.
## <Enter> Play 1 "Tentacles" token in a zone adjacent to this card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func can_monster_advance(_ctx: EffectContext) -> bool:
	return false


func can_monster_invade(_ctx: EffectContext) -> bool:
	return false


func on_enter(ctx: EffectContext) -> void:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1

	# Rule 5.11.1.2: adjacent zones, avoiding monster zone if possible
	var adjacent := get_adjacent_zones(monster_zone_idx)
	var valid: Array[int] = []
	for zi in adjacent:
		if zi != monster_zone_idx:
			valid.append(zi)

	if valid.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid,
		"Choose an adjacent zone for a Tentacles token:")
	if chosen < 0:
		return

	await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP02-T02", chosen)
