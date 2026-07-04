extends CardEffect
## EBP04-037: Minilla(2004) - Battle Rank 3 (Red)
## If you have a rank 1 strategy card in play, this card gains +3000 counter
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
		if not sz_card.is_empty() and sz_card.get("rank", 99) == 1:
			return 3000
	return 0
