extends CardEffect

## ESD05-001: King Ghidorah(1991) - Monster Rank 3 (Green)
## <Enter> Send cards from the top of your deck to your discard pile equal to
## the number of the zone this card is in.
##
## Tested: Yes
## Known issues: None
## Edge cases: Mills only what the deck holds when it is shorter.
## Rules: None
## Interactions: None
## Implementation notes: "The zone this card is in" for a monster card =
##   owner.monster_zone (1-based), read when the Enter resolves.


func get_bot_tags() -> Array[String]:
	return ["mill_self"]


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.monster_zone > 0:
		await ctx.mill(ctx.owner.monster_zone)
