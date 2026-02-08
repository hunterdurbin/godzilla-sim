extends CardEffect

## EBP02-052: SpaceGodzilla Flying Form - Monster Rank 1 (Green)
## <When Invading> You may discard 1 card from your hand, if you do,
## play 1 "Crystals" token.


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if ctx.owner.hand.is_empty():
		return

	# Let the player choose a card to discard (any card, optional)
	var selected: Dictionary = await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(_card: Dictionary) -> bool: return true,
		"Discard a card to play a Crystals token (or skip):",
		true)

	if selected.is_empty():
		return

	# Place a Crystals token in an empty zone
	await ctx.effect_handler.create_tokens_in_empty_zones(ctx.owner, "EBP02-T03", 1)
