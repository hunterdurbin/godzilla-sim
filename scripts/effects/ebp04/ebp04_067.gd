extends CardEffect
# Godzilla Earth (Battle)
# Can only be played in area 8.
# <Enter> Play 1 [Godzilla Earth] Token in own area 3.
# If this card or token are moved/not in zone, Destroy both.


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func can_be_played(ctx: EffectContext, zone_index: int) -> bool:
	return zone_index == 7  # Zone 8 = index 7


func on_enter(ctx: EffectContext) -> void:
	# Play Godzilla Earth Token in zone 3 (index 2)
	if not ctx.owner.zones[2].is_empty():
		return
	await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP04-T01", 2)
