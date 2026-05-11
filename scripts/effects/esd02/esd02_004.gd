extends CardEffect

## ESD02-004: Godzilla(1994) - Monster Rank 4
## <When Invading> Discard 1 battle card from your hand： <Destroy> all of your
## opponent's battle cards with a rank equal to or lower than the discarded card’s rank.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func bot_can_fulfill_on_when_invading(owner: PlayerState, _opponent: PlayerState) -> bool:
	for card in owner.hand:
		if card.get("card_type") == CardEnums.CardType.BATTLE:
			return true
	return false


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	# Cost: discard 1 battle card from hand (optional — player may skip)
	var discarded := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("card_type") == CardEnums.CardType.BATTLE,
		tr("STR_EFF_ESD02_004_PROMPT"),
		true # allow_skip
	)
	if discarded.is_empty():
		return

	# Destroy all opponent battle cards with rank <= discarded card's rank
	var max_rank: int = discarded.get("rank", 0)
	var zones_to_destroy: Array[int] = []
	for i in range(8):
		var zone_card := ctx.opponent.get_zone_top_card(i)
		if not zone_card.is_empty() and ctx.field_rank(zone_card, ctx.opponent.player_id) <= max_rank:
			zones_to_destroy.append(i)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
