extends CardEffect
## EBP04-067: Godzilla Earth - Battle Rank 7 (Green)
## You can only play this card in Area 8.
## <Enter> Play 1 [Godzilla Earth] Token in your area 3. 
## If this card and the token are not in an area, or they are moved, <Destroy> both.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func get_required_play_zones(_ctx: EffectContext) -> Array[int]:
	return [7] # Zone 8 only (index 7)


func on_enter(ctx: EffectContext) -> void:
	# Continuous link: if the token can't be placed in zone 3, destroy self
	# per the second clause. The owner's monster occupying zone 3 blocks
	# placement (monster_zone is tracked separately from zones[]).
	var placed := false
	if ctx.owner.monster_zone != 3:
		placed = await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP04-T01", 2)
	if placed:
		return
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone >= 0:
		await ctx.effect_handler.destroy_zones(ctx.owner, [my_zone])


func on_leave_play(ctx: EffectContext, _zone_idx: int) -> void:
	# Continuous link: destroying, overloading, banishing, or otherwise removing
	# this card from a zone takes the linked token with it.
	var token_zone: int = _find_token_zone(ctx)
	if token_zone >= 0:
		await ctx.effect_handler.destroy_zones(ctx.owner, [token_zone])


func on_zone_changed(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	# Movement triggers "destroy both" — destroy self; on_leave_play chains the token.
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone >= 0:
		await ctx.effect_handler.destroy_zones(ctx.owner, [my_zone])


func _find_token_zone(ctx: EffectContext) -> int:
	for i in range(8):
		if CardUtils.base_id(ctx.owner.get_zone_top_card(i)) == "EBP04-T01":
			return i
	return -1
