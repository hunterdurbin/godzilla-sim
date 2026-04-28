extends CardEffect
## EBP04-081: Twisting Terror - Strategy Rank 3 (Blue)
## <Your Turn> Your monster card cannot advance nor invade.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"can_monster_advance": {"own_turn": true},
	"can_monster_invade": {"own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return []


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func can_monster_advance(_ctx: EffectContext) -> bool:
	return false


func can_monster_invade(_ctx: EffectContext) -> bool:
	return false
