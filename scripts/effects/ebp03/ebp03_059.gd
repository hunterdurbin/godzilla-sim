extends CardEffect
# Cretaceous King Ghidorah(1998) (Battle R5)
# <Revenge> Return up to 1 King Ghidorah monster card from discard to hand.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func bot_can_fulfill_on_revenge(owner: PlayerState, _opponent: PlayerState) -> bool:
	for card in owner.discard_pile:
		if CardUtils.is_monster(card) \
			and CardUtils.has_trait(card, CardEnums.CardTrait.KING_GHIDORAH):
			return true
	return false


func on_revenge(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card): return CardUtils.is_monster(card) \
			and CardUtils.has_trait(card, CardEnums.CardTrait.KING_GHIDORAH),
		tr("STR_EFF_EBP03_059_PROMPT")
	)
	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
