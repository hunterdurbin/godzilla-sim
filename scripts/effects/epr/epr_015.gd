extends CardEffect

## EPR-015: Godzilla(GODZILLA THE RIDE: GREAT CLASH) - Battle Rank 6 (Red)
## If you have a card with <《GODZILLA THE RIDE》> in your discard pile, this
## card gains +5000 counter power.
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
	for card in ctx.owner.discard_pile:
		if CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA_THE_RIDE):
			return 5000
	return 0
