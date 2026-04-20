extends CardEffect
# Godzilla (2004)
# Each time you Destroy an opponent's battle card in the same column as this card,
# if you have a Rank 1 strategy card in play, opponent discards to 2.
# Note: Triggered via trigger_zone_destroyed callback — uses on_battle_card_played
# as the closest existing hook. TODO: needs on_zone_card_destroyed hook for full accuracy.


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "column_dependent_monster_self"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
