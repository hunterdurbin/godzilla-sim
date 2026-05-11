extends CardEffect
## EBP04-038: Kamacuras - Battle Rank 3 (Red)
## If you have 2 or more other battle cards in your zones, this card gains +3000 counter
## power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var my_zone: int = find_zone_of_card(ctx)
	var occupied: Array[int] = ctx.owner.get_battle_card_zone_indices()
	var count: int = occupied.size()
	if my_zone in occupied:
		count -= 1
	return 3000 if count >= 2 else 0
