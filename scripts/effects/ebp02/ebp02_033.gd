extends CardEffect

## EBP02-033: Little Godzilla - Battle Rank 5 (Blue)
## <Awakening4> This card gains +3000 counter power. (Active if your monster card is in
## zone 4 or beyond.)
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
	if ctx.is_awakening(4):
		return 3000
	return 0
