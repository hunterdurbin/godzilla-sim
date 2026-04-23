extends CardEffect
## EBP04-067: Godzilla Earth - Battle Rank 7 (Green)
## You can only play this card in Area 8.
## <Enter> Play 1 [Godzilla Earth] Token in your area 3. If this card and the
## token are not in an area, or they are moved, <Destroy> both.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func get_required_play_zones(_ctx: EffectContext) -> Array[int]:
	return [7]  # Zone 8 only (index 7)


func on_enter(ctx: EffectContext) -> void:
	var top: Dictionary = ctx.owner.get_zone_top_card(2)
	if top.get("card_type") == CardEnums.CardType.MONSTER:
		return
	await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP04-T01", 2)


func on_destroy(ctx: EffectContext, _zone_idx: int) -> void:
	# Destroy linked token in zone 3 when this card is destroyed
	var token: Dictionary = ctx.owner.get_zone_top_card(2)
	if token.get("id") == "EBP04-T01":
		await ctx.effect_handler.destroy_zones(ctx.owner, [2])


func on_zone_changed(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	# Destroy linked token in zone 3 when this card is moved
	var token: Dictionary = ctx.owner.get_zone_top_card(2)
	if token.get("id") == "EBP04-T01":
		await ctx.effect_handler.destroy_zones(ctx.owner, [2])
