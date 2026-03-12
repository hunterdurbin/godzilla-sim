extends CardEffect

## EBP01-039: Godzilla(1999) - Monster Rank 2 (Blue)
## <When Invading> Discard 1 monster card from your hand: <Destroy> all of your
## opponent's rank 5 or lower battle cards in zones 1-5.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	var discarded := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("card_type") == CardEnums.CardType.MONSTER,
		"Discard a monster card to destroy opponent's rank 5 or lower cards in zones 1-5:",
		true # allow_skip
	)
	if discarded.is_empty():
		return

	# Destroy rank 5 or lower in zones 1-5 (indices 0-4)
	var zones_to_destroy: Array[int] = []
	for i in range(5):
		var zone_card := ctx.opponent.get_zone_top_card(i)
		if not zone_card.is_empty() and ctx.field_rank(zone_card, ctx.opponent.player_id) <= 5:
			zones_to_destroy.append(i)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
