extends CardEffect

## EBP02-061: Godzilla(1972) - Battle Rank 4 (Green)
## If this card is in zone 8, this card gains +3000 counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "zone_dependent"]


func get_bot_preferred_zones() -> Array[int]:
	return [7]  # zone 8 (0-indexed)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx == 7:
		return 3000
	return 0
