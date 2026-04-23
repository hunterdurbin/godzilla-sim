extends CardEffect
# Kaiser Ghidorah
# Can play on top of a Monster X monster card in own zones.
# <Enter> If 3+ colors of battle cards in discard → opp rage -1.


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func can_play_as_monster(ctx: EffectContext) -> bool:
	if ctx.card_data.get("played_from_effect", false):
		return false
	return CardEnums.CardTrait.MONSTER_X in ctx.owner.current_monster.get("traits", [])


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.rage > 0


func on_enter(ctx: EffectContext) -> void:
	if _count_discard_colors(ctx) < 3:
		return
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)


func _count_discard_colors(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			for c: int in card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size()
