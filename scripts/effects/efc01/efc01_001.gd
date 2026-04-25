extends CardEffect

## EFC01-001: Godzilla(Gojika Festival) - Monster Rank 4 (Red)
## <Burst3>
## If every zone adjacent to this card's zone has a battle card with <Fest>,
## this card gains +10000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_burst_rank() -> int:
	return 3


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	if monster_zone_idx < 0:
		return 0
	var adjacent := get_adjacent_zones(monster_zone_idx)
	if adjacent.is_empty():
		return 0
	for zone_idx in adjacent:
		var card := ctx.owner.get_zone_top_card(zone_idx)
		if card.is_empty():
			return 0
		if not CardUtils.is_battle(card):
			return 0
		if not CardUtils.has_trait(card, CardEnums.CardTrait.FEST):
			return 0
	return 10000
