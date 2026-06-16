extends CardEffect
# Primitive Mothra (Battle R3)
# <Enter> You may put up to 1 <《Mothra》> battle card from your discard pile on top of
# your deck.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["heals_deck"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	for card in owner.discard_pile:
		if CardUtils.is_battle(card) \
			and CardUtils.has_trait(card, CardEnums.CardTrait.MOTHRA):
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card): return CardUtils.is_battle(card) \
			and CardUtils.has_trait(card, CardEnums.CardTrait.MOTHRA),
		tr("STR_EFF_EBP03_055_PROMPT")
	)
	if not selected.is_empty():
		ctx.effect_handler.put_card_on_top_of_deck(ctx.owner.player_id, selected)
