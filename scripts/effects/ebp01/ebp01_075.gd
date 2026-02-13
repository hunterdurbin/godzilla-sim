extends CardEffect

## EBP01-075: Godzilla, King of the Monsters - Battle Rank 8 (White)
## This card gains +3000 counter power for each of your monster card's <Rage>.
## If your monster card has 3 or more <Rage>, and this card is in zones 1-5, this card
## cannot be <Destroy> by your opponent's effects.
## <Awakening8> You can play this card with its rank reduced by 4.
## (Active if your monster card is in zone 8. After being played, this card is rank 8.)
##
## NOTE: Destruction protection and rank reduction require system-level support.
## The CP modifier is fully implemented.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	return 3000 * ctx.owner.rage


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
