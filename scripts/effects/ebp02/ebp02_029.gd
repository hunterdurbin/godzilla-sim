extends CardEffect

## EBP02-029: Biollante Plant Beast Form - Monster Rank 4 (Blue)
## <Opponent's Turn> At the beginning of the counter phase, for the rest of the turn,
## double the counter power of all of your opponent's battle cards in the same column
## as this card. (Refer to those battle card's counter power at the ability resolution timing.)


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_opponent_zone_cp_modifiers(ctx: EffectContext) -> Dictionary:
	# Only active during opponent's turn
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return {}
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	if monster_zone_idx < 0:
		return {}
	var column_zones := get_opponent_column_zones(monster_zone_idx)
	var mods: Dictionary = {}
	for zi in column_zones:
		var opp_card: Dictionary = ctx.opponent.get_zone_top_card(zi)
		if not opp_card.is_empty():
			var cp: int = opp_card.get("counter_power", 0)
			if cp > 0:
				mods[zi] = cp  # Adding base CP again = doubling
	return mods
