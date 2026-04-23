extends CardEffect
## EBP04-076: Dormancy - Strategy Rank 2 (Red)
## <Base>
## Your monster card cannot be moved by any of your opponent's effects. (Move
## when you are countered)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["protects_cards"]


func is_base_strategy() -> bool:
	return true


func prevents_opponent_monster_move(_ctx: EffectContext) -> bool:
	return true


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
