extends CardEffect

## EBP02-040: Interception Operation - Strategy Rank 7 (Blue)
## If you have 5 or more <《Weapon》> battle cards with “MB” in their name in your zones,
## discard your hand and draw 5 cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	var mb_weapon_count: int = owner.count_zones_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.has_trait(c, CardEnums.CardTrait.WEAPON) and "MB" in c.get("name", ""))
	return mb_weapon_count >= 5


func on_enter(ctx: EffectContext) -> void:
	var mb_weapon_count: int = ctx.owner.count_zones_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.has_trait(c, CardEnums.CardTrait.WEAPON) and "MB" in c.get("name", ""))

	if mb_weapon_count < 5:
		return

	# Discard entire hand, then draw 5
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, 0)
	ctx.owner.draw_cards(5)
