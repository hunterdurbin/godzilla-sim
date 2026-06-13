extends CardEffect

## EBP02-065: Godzilla(1991) - Battle Rank 6 (Green)
## <Awakening6> If there are 3 or more cards under your monster card, this card gains
## +5000 counter power. If there are 5 or more, this card gains an additional +5000
## counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp"]


func bot_can_fulfill_counter_power(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.is_awakening(6) and owner.has_monster_stack(3)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if not ctx.is_awakening(6):
		return 0

	var cards_under: int = ctx.owner.monster_stack.size()
	if cards_under >= 5:
		return 10000
	elif cards_under >= 3:
		return 5000
	return 0
