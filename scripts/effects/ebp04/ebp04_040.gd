extends CardEffect
## EBP04-040: Anguirus(2004) - Battle Rank 5 (Red)
## <Awakening 6> <Enter> If you have at least 1 《Rodan》 battle card and at least 1 《King
## Caesar》 battle card in your zones, increase your monster card’s <Rage> by 3. (Active
## if your monster card is in zone 6 or beyond.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func on_enter(ctx: EffectContext) -> void:
	if not ctx.is_awakening(6):
		return

	var has_rodan: bool = ctx.owner.has_zone_matching(
		func(c: Dictionary) -> bool: return CardUtils.has_trait(c, CardEnums.CardTrait.RODAN))
	var has_king_caesar: bool = ctx.owner.has_zone_matching(
		func(c: Dictionary) -> bool: return CardUtils.has_trait(c, CardEnums.CardTrait.KING_CAESAR))

	if not (has_rodan and has_king_caesar):
		return

	await ctx.effect_handler.gain_rage(ctx.owner.player_id, 3, ctx.card_data.get("id", ""))
