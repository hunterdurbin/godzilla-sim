extends CardEffect

## ESD03-001: Godzilla(2026) - Monster Rank 1 (Red)
## <When Invading> If this card invades by discarding a monster card from your
## hand, increase this card's <Rage> by 1. (If this card invades 2 zones, this
## activates twice.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: on_when_invading fires once per zone advanced, so an
##   invade-2 monster discard gains 2 Rage naturally. The discarded card is
##   read from PlayerState.last_invasion_card (as EBP02-022).


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func bot_can_fulfill_on_when_invading(owner: PlayerState, _opponent: PlayerState) -> bool:
	for card in owner.hand:
		if CardUtils.is_monster(card) and int(card.get("invasion_icon", 0)) > 0:
			return true
	return false


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if not CardUtils.is_monster(ctx.owner.last_invasion_card):
		return
	await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1, ctx.card_data.get("id", ""))
