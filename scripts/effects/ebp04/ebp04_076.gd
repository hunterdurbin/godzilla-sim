extends CardEffect
# Dormancy
# <Base>
# Your monster card cannot be moved by any of your opponent's effects.
# Note: prevents_opponent_monster_move is a new mechanism.
# TODO: add virtual to card_effect.gd, check in ActionHandler wherever opponent's
# effect would set monster zone (retreat_monster_to_zone, advance_monster_to_zone, etc.)


func get_bot_tags() -> Array[String]:
	return ["protects_cards"]


func is_base_strategy() -> bool:
	return true


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
