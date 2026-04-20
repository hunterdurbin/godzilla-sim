extends CardEffect
# Dormancy
# <Base>
# Your monster card cannot be moved by any of your opponent's effects.
# prevents_opponent_monster_move is wired into EffectHandler.is_opponent_monster_move_blocked(),
# checked by effect scripts (e.g. EBP04-078) before moving the opponent's monster.


func get_bot_tags() -> Array[String]:
	return ["protects_cards"]


func is_base_strategy() -> bool:
	return true


func prevents_opponent_monster_move(_ctx: EffectContext) -> bool:
	return true


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
