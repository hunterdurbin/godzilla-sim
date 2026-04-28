extends CardEffect
## EBP04-T01: Godzilla Earth - Battle Rank 7 (Green)
## (Tokens cannot be added to the deck. They are banished when removed from
## zones.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_leave_play(ctx: EffectContext, _zone_idx: int) -> void:
	# Continuous link: any way the token leaves a zone takes the linked
	# Godzilla Earth with it.
	var partner_zone: int = _find_partner_zone(ctx)
	if partner_zone >= 0:
		await ctx.effect_handler.destroy_zones(ctx.owner, [partner_zone])


func on_zone_changed(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	# Movement triggers "destroy both" — destroy self; on_leave_play chains the partner.
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone >= 0:
		await ctx.effect_handler.destroy_zones(ctx.owner, [my_zone])


func _find_partner_zone(ctx: EffectContext) -> int:
	for i in range(8):
		if ctx.owner.get_zone_top_card(i).get("id", "") == "EBP04-067":
			return i
	return -1
