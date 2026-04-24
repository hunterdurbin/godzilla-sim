extends CardEffect
## EBP04-007: Godzilla (1962) - Monster Rank 4 (Red)
## <Burst III>
## When you invade with <Invade 1>, this advances 2 zones.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_self"]


func get_burst_rank() -> int:
	return 3


func get_invasion_advance_bonus(_ctx: EffectContext, invasion_icon: int) -> int:
	if invasion_icon == 1:
		return 1
	return 0
