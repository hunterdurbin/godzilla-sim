extends CardEffect
# Kaiser Ghidorah (Battle)
# +5000 counter power per color of battle card in discard.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			for c: int in card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size() * 5000
