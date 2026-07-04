extends CardEffect

## EBP01-051: Orga Phase II - Battle Rank 4 (Blue)
## If you have 5 or more monster cards in your discard pile, this card gains
## +3000 counter power.
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
	if CardUtils.count_monsters_in_discard(ctx.owner.discard_pile) >= 5:
		return 3000
	return 0
