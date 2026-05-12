extends CardEffect
## EBP04-082: X-Aliens' Mother Ship - Strategy Rank 5 (Blue)
## <Base>When any monster card invades into zones 6–8,  <Destroy> this card.  (Cards
## with Base are not sent to the discard pile at the start phase.)
## <Your Turn> All of your non-blue battle cards in zones adjacent to your monster card
## gain +3000 counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func is_base_strategy() -> bool:
	return true


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_field_cp_modifiers(ctx: EffectContext) -> Dictionary:
	if ctx.is_opponent_turn():
		return {}

	var monster_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_idx)
	var mods: Dictionary = {}

	for zi in adjacent:
		var zone_card := ctx.owner.get_zone_top_card(zi)
		if zone_card.is_empty() or not CardUtils.is_battle(zone_card):
			continue
		if CardUtils.has_color(zone_card, CardEnums.CardColor.BLUE):
			continue
		mods[zi] = mods.get(zi, 0) + 3000

	return mods
