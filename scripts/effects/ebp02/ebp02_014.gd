extends CardEffect

## EBP02-014: Cabinet Helicopter - Battle Rank 6 (Red)
## <Enter> Send the top card of your deck to your discard pile.
## If it is a monster card, advance your monster card to zone 6.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.main_deck.is_empty():
		return

	var card: Dictionary = ctx.owner.main_deck.pop_front()
	ctx.owner.discard_pile.append(card)
	ctx.owner.deck_changed.emit()
	ctx.owner.discard_changed.emit()

	if card.get("card_type") == CardEnums.CardType.MONSTER:
		if ctx.owner.monster_zone < 6:
			var old_zone: int = ctx.owner.monster_zone
			ctx.owner.monster_zone = 6
			ctx.owner.monster_changed.emit()
			await ctx.effect_handler.trigger_monster_advance(ctx.owner.player_id, old_zone, 6)
