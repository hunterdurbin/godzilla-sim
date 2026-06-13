extends CardEffect

## EBP02-047: King Ghidorah(1991) - Monster Rank 1 (Green)
## Whenever this card advances, send the top card of your deck to your discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self"]


func on_monster_advance(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await ctx.mill_one()
