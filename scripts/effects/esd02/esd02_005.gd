extends CardEffect

## ESD02-005: Godzilla(1993) - Monster Rank 3
## <When Invading> Reduce your opponent's <Rage> by 1.
## (If you invaded 2 zones, activate this effect 2 times.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func bot_can_fulfill_on_when_invading(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.rage > 0


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if ctx.opponent.rage > 0:
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
