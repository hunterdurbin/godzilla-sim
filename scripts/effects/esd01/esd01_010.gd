extends CardEffect

## ESD01-010: City of Tokyo - Battle Rank 6
## If your monster card has 2 or more <Rage>, your other battle card in zone 8
## gains +5000 counter power.
## <Awakening6> Your other battle card in zone 8 gains +5000 counter power.
## (Active if your monster card is in zone 6 or beyond.)


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_counter_power_modifier(_ctx: EffectContext) -> int:
	return 0


func get_field_cp_modifiers(ctx: EffectContext) -> Dictionary:
	# "other" — don't boost zone 8 if this card itself is in zone 8
	if find_zone_of_card(ctx) == 7:
		return {}

	# Only applies if there's a battle card in zone 8
	var zone8_card := ctx.owner.get_zone_top_card(7)
	if zone8_card.is_empty() or zone8_card.get("card_type") != CardEnums.CardType.BATTLE:
		return {}

	var bonus := 0
	# Base: +5000 if rage >= 2
	if ctx.owner.rage >= 2:
		bonus += 5000
	# Awakening6: +5000 if monster in zone 6+
	if ctx.owner.monster_zone >= 6:
		bonus += 5000

	if bonus == 0:
		return {}
	return {7: bonus}
