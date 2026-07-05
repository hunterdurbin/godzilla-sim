extends CardEffect

## ESC01-004: Godzilla(2023) - Battle Rank 6 (Red)
## If your monster card has 3 or more <Rage>, this card gains +5000 counter power.
## If this card would be <Destroy>, place it on the bottom of your deck instead.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: Replacement effect — the card never counts as destroyed (no revenge).
## Interactions: None
## Implementation notes: None


## CP modifier is placement-independent — safe to preview while in hand.
const HAND_CP_PREVIEW := true


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "heals_deck"]


func bot_can_fulfill_counter_power(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.rage >= 3


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.owner.rage >= 3:
		return 5000
	return 0


func on_would_be_destroyed(_ctx: EffectContext) -> bool:
	# Move to deck bottom instead of being destroyed
	return true
