extends CardEffect
# Primitive Mothra (Battle R3)
# <Enter> Put up to 1 Mothra battle card from discard on top of deck.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["heals_deck"]


func on_enter(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.BATTLE \
			and CardEnums.CardTrait.MOTHRA in card.get("traits", []),
		"Put a Mothra battle card from discard on top of deck (or skip):"
	)
	if not selected.is_empty():
		ctx.owner.main_deck.push_front(selected)
		ctx.owner.deck_changed.emit()
