extends CardEffect

## ESD05-003: Dorat - Battle Rank 3 (Green)
## <Dominate> <Enter> Send the top 3 cards of your deck to your discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: <Dominate> = ctx.is_dominate(), checked on entry.


func get_bot_tags() -> Array[String]:
	return ["mill_self"]


func bot_can_fulfill_on_enter(owner: PlayerState, opponent: PlayerState) -> bool:
	return owner.monster_zone >= opponent.monster_zone


func on_enter(ctx: EffectContext) -> void:
	if ctx.is_dominate():
		await ctx.mill(3)
