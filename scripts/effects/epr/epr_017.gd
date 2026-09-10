extends CardEffect

## EPR-017: Godzilla(GODZILLA THE RIDE: GREAT CLASH) - Battle Rank 5 (Green)
## <Enter> Place 1 card with <《GODZILLA THE RIDE》> from your discard pile under
## your monster card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Mandatory when a RIDE card is in the discard pile
## (no skip); search_discard force-skips when nothing matches.


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	for card in owner.discard_pile:
		if CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA_THE_RIDE):
			return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var selected: Dictionary = await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.has_trait(card, CardEnums.CardTrait.GODZILLA_THE_RIDE),
		tr("STR_EFF_EPR_017_PROMPT"),
		false)

	if selected.is_empty():
		return

	ctx.owner.monster_stack.append(selected)
	ctx.owner.monster_changed.emit()
