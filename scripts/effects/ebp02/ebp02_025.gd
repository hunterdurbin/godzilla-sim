extends CardEffect

## EBP02-025: Biollante Rose Form - Monster Rank 2 (Blue)
## This card cannot advance nor invade.
## <Enter> Play 1 “Tentacles” token in a zone adjacent to this card. (Tokens are
## prepared separately from your main deck.)
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

	var valid := CardEffect.get_effect_play_adjacent_zones(ctx.owner, monster_zone_idx)

	if valid.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid,
		tr("STR_EFF_EBP02_025_PROMPT"))
	if chosen < 0:
		return

	await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP02-T02", chosen)
