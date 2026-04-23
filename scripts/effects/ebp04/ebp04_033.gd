extends CardEffect
## EBP04-033: Kaiser Ghidorah - Monster Rank 3 (Red, Blue, Green)
## You can play this on top of a <Monster X> monster card in your zones.
## <Enter> If you have 3 or more colors of battle cards in your discard pile,
## decrease your opponent's <Rage> by 1.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


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
