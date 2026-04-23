extends CardEffect
## EBP04-040: Anguirus (2004) - Battle Rank 5 (Red)
## <Awakening 6> <Enter> If you have 1 or more <Rodan> and <King Caesar>
## battle cards each in your zones, increase your monster card's <Rage> by 3.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone < 6:
		return

	var has_rodan := false
	var has_king_caesar := false
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		var traits: Array = zone_card.get("traits", [])
		if CardEnums.CardTrait.RODAN in traits:
			has_rodan = true
		if CardEnums.CardTrait.KING_CAESAR in traits:
			has_king_caesar = true

	if not (has_rodan and has_king_caesar):
		return

	var old_rage := ctx.owner.rage
	ctx.owner.rage += 3
	ctx.owner.rage_changed.emit(ctx.owner.rage)
	await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
