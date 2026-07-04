extends CardEffect
## EBP04-060: Vulture - Battle Rank 4 (Green)
## If you have a card named “Mechagodzilla City” in play, this card gains +3000 counter
## power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


## CP modifier is placement-independent — safe to preview while in hand.
const HAND_CP_PREVIEW := true


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	for sz_card in ctx.owner.strategy_zones:
		if sz_card.get("name", "") == "Mechagodzilla City":
			return 3000
	return 0
