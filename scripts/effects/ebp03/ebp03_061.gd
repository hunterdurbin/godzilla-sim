extends CardEffect

## EBP03-061: Dagahra - Battle Rank 6 (Green)
## When you discard this card from your hand for your monster card's invasion, you may
## play this card from your discard pile.
## <Awakening6> This card gains +3000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "boosts_cp"]


func bot_can_fulfill_counter_power(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.monster_zone >= 6


func on_discarded_for_invasion(_ctx: EffectContext) -> bool:
	# Play self from discard pile (handled by ActionHandler/EffectHandler)
	return true


func get_counter_power_modifier(ctx: EffectContext) -> int:
	# Awakening6: monster in zone 6+
	if ctx.owner.monster_zone >= 6:
		return 3000
	return 0
