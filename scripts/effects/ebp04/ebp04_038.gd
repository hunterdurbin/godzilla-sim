extends CardEffect
# Kamacuras
# If there are 2 or more other battle cards in own zones → +3000 counter power.


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var my_zone: int = find_zone_of_card(ctx)
	var count: int = 0
	for i in range(8):
		if i == my_zone:
			continue
		if ctx.owner.zone_has_cards(i):
			count += 1
	return 3000 if count >= 2 else 0
