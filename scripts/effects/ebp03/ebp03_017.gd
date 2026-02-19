extends CardEffect

## EBP03-017: Godzilla(2003) - Monster Rank 4 (Blue)
## Whenever you discard a battle card from your hand, reduce your opponent's Rage by 1.
## If your opponent's Rage is 0, increase this card's Rage by 1 instead.
## <Enter> You may discard 1 battle card from your hand. If you do, Destroy 1 of your
## opponent's rank 6 or lower battle cards.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func on_hand_card_discarded(ctx: EffectContext, discarded_card: Dictionary) -> void:
	if discarded_card.get("card_type") != CardEnums.CardType.BATTLE:
		return
	if ctx.opponent.rage > 0:
		var old_rage: int = ctx.opponent.rage
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.opponent.player_id, old_rage, ctx.opponent.rage)
	else:
		var old_rage: int = ctx.owner.rage
		ctx.owner.rage += 1
		ctx.owner.rage_changed.emit(ctx.owner.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)


func on_enter(ctx: EffectContext) -> void:
	# Discard 1 battle card from hand (optional)
	var selected: Dictionary = await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return card.get("card_type") == CardEnums.CardType.BATTLE,
		"Discard a battle card to destroy an opponent's rank 6 or lower battle card (or skip):",
		true)

	if selected.is_empty():
		return

	# Destroy 1 opponent R6 or lower battle card
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
		"Choose an opponent's rank 6 or lower battle card to destroy:")
