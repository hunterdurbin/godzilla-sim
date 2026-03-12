extends CardEffect

## EBP01-074: King Ghidorah(2024) - Battle Rank 8 (White)
## If you have a card named "Gravity Beam" in play, this card gains +20,000 counter power.
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
	# Check strategy zones for "Gravity Beam"
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("name", "") == "Gravity Beam":
			return 20000
	return 0
