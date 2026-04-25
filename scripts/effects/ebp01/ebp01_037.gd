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
			return CardUtils.is_strategy(card),
		tr("STR_EFF_EBP01_037_PROMPT"),
		true # allow_skip
	)
	if not discarded.is_empty():
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1)
