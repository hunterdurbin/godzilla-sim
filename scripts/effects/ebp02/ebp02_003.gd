extends CardEffect

## EBP02-003: Godzilla(2016) 2nd Form - Monster Rank 2 (Red)
## <Burst3>
## <Enter> If there is a card named "Giant Unknown Creature" under this card,
## you may discard 1 strategy card from your hand to advance this card by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_burst_rank() -> int:
	return 3


func on_enter(ctx: EffectContext) -> void:
	var has_guc: bool = false
	for card in ctx.owner.monster_stack:
		if card.get("name", "") == "Giant Unknown Creature":
			has_guc = true
			break

	if not has_guc:
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("card_type") == CardEnums.CardType.STRATEGY,
		"Discard a strategy card to advance by 1 zone (or skip):",
		true)

	if not selected.is_empty():
		if ctx.owner.monster_zone < 8:
			var old_zone: int = ctx.owner.monster_zone
			ctx.owner.monster_zone += 1
			ctx.owner.monster_changed.emit()
			await ctx.effect_handler.trigger_monster_advance(ctx.owner.player_id, old_zone, ctx.owner.monster_zone)
