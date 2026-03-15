extends CardEffect

## EBP01-037: Godzilla(1995) - Monster Rank 3 (Blue)
## Whenever this card advances, you may discard 1 strategy card from your hand
## to increase its <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_self"]


func on_monster_advance(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	var discarded := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("card_type") == CardEnums.CardType.STRATEGY,
		"Discard a strategy card from hand to gain 1 Rage:",
		true # allow_skip
	)
	if not discarded.is_empty():
		ctx.owner.rage += 1
		ctx.owner.rage_changed.emit(ctx.owner.rage)
