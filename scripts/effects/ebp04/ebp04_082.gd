extends CardEffect
# X-Aliens' Mother Ship
# <Base>
# <Your Turn> All non-blue battle cards in zones adjacent to own monster → +3000 CP.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func is_base_strategy() -> bool:
	return true


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_field_cp_modifiers(ctx: EffectContext) -> Dictionary:
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return {}

	var monster_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_idx)
	var mods: Dictionary = {}

	for zi in adjacent:
		var zone_card := ctx.owner.get_zone_top_card(zi)
		if zone_card.is_empty() or zone_card.get("card_type") != CardEnums.CardType.BATTLE:
			continue
		if CardEnums.CardColor.BLUE in zone_card.get("colors", []):
			continue
		mods[zi] = mods.get(zi, 0) + 3000

	return mods
