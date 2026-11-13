extends CardEffect

## Test-only effect: "This card cannot be <Destroy>" with no opponent-only
## gate. No printed card does this yet (every protection is "by your
## opponent's effects"); used to cover the protected-card path of
## self-destroy effects like ESD05-005.


func can_be_destroyed(_ctx: EffectContext) -> bool:
	return false
