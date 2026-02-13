extends CardEffect

## EBP02-059: Godzillasaurus - Battle Rank 3 (Green)
## <Revenge> You may discard 1 card from your hand, if you do, return 1 battle card
## named "Godzilla(1991)" from your discard pile to your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_revenge(ctx: EffectContext) -> void:
	# Check if there's a matching card in discard first
	var has_target: bool = false
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.BATTLE and card.get("name", "") == "Godzilla(1991)":
			has_target = true
			break

	if not has_target:
		return

	var discarded := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(_card: Dictionary) -> bool: return true,
		"Discard a card to return Godzilla(1991) from discard (or skip):",
		true)

	if discarded.is_empty():
		return

	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("card_type") == CardEnums.CardType.BATTLE and card.get("name", "") == "Godzilla(1991)",
		"Choose a Godzilla(1991) battle card to return to your hand:")

	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
