extends CardEffect

## EBP02-009: Godzilla(2023) - Monster Rank 4 (Red)
## <Burst3> (You can play this card from rank III. If you do, send this card to your
## discard pile at the beginning of your next end phase.)
## When this card is discarded by the effect of Burst, return this card from your
## discard pile to your hand.
## <When Invading> Your opponent discards cards until they have 3 cards remaining in
## their hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand"]


func get_burst_rank() -> int:
	return 3


func on_burst_discard(ctx: EffectContext) -> void:
	# Return this card from discard pile to hand
	var card_id: String = ctx.card_data.get("id", "")
	for i in range(ctx.owner.discard_pile.size() - 1, -1, -1):
		if ctx.owner.discard_pile[i].get("id", "") == card_id:
			var card: Dictionary = ctx.owner.discard_pile.pop_at(i)
			ctx.owner.hand.append(card)
			ctx.owner.hand_changed.emit()
			ctx.owner.discard_changed.emit()
			return


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 3)
