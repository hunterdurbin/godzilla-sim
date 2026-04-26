extends CardEffect
## EBP04-081: Twisting Terror - Strategy Rank 3 (Blue)
## <Your Turn> Your monster card cannot advance nor invade.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return []


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func prevents_own_invasion(ctx: EffectContext) -> bool:
	return ctx.is_own_turn()


func can_monster_advance(ctx: EffectContext) -> bool:
	return ctx.is_opponent_turn()
