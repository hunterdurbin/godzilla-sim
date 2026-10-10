extends CardEffect

## ESD05-004: Godzillasaurus - Battle Rank 5 (Green)
## If there is a card under your monster card, this card gains +3000 counter
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


func bot_can_fulfill_counter_power(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.has_monster_stack(1)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	return 3000 if ctx.has_monster_stack(1) else 0
