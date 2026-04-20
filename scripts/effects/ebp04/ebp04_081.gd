extends CardEffect
# Twisting Terror
# <Base>
# <Your Turn> Your monster card cannot advance nor invade.


func get_bot_tags() -> Array[String]:
	return []


func is_base_strategy() -> bool:
	return true


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func prevents_own_invasion(ctx: EffectContext) -> bool:
	return ctx.game_state.current_player_id == ctx.owner.player_id


func can_monster_advance(ctx: EffectContext) -> bool:
	return ctx.game_state.current_player_id != ctx.owner.player_id
