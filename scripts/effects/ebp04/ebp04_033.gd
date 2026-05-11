extends CardEffect
## EBP04-033: Kaiser Ghidorah - Monster Rank 3 (Red, Blue, Green)
## This card can be played by placing it on top of a monster card with 《Monster X》 in
## your zones.
## <Enter> If there are 3 or more different colors among battle cards in your discard
## pile, reduce your opponent’s <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


## Predecessor traits this card accepts as an alt rank-up bridge. Used by
## DeckValidator to suppress the no-shared-traits warning.
const RANKUP_ALT_PREDECESSOR_TRAITS := [CardEnums.CardTrait.MONSTER_X]


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent"]


func can_play_as_monster(ctx: EffectContext) -> bool:
	if ctx.card_data.get("played_from_effect", false):
		return false
	return CardUtils.has_trait(ctx.owner.current_monster, CardEnums.CardTrait.MONSTER_X)


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return opponent.has_rage()


func on_enter(ctx: EffectContext) -> void:
	if _count_discard_colors(ctx) < 3:
		return
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)


func _count_discard_colors(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card):
			for c: int in card.get("colors", []):
				if c not in colors:
					colors.append(c)
	return colors.size()
