extends CardEffect

## EBP02-003: Godzilla(2016) 2nd Form - Monster Rank 2 (Red)
## <Burst3> (You can play this card from rank III. If you do, send this card to your
## discard pile at the beginning of your next end phase.)
## <Enter> If there is a card named “Giant Unknown Creature” under this card, you may
## discard 1 strategy card from your hand to advance this card by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_self"]


func get_bot_max_advance_zone(owner: PlayerState, _opponent: PlayerState) -> int:
	return mini(owner.monster_zone + 1, 8)


func get_bot_advance_reliability(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 100


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	# Check active monster and stack — GUC will be in the stack by the time
	# this card is played (it gets stacked when ranked up from).
	if owner.current_monster.get("name", "") == "Giant Unknown Creature":
		return true
	for card in owner.monster_stack:
		if card.get("name", "") == "Giant Unknown Creature":
			return true
	return false


func get_bot_effect_costs() -> Array[Dictionary]:
	return [ {"card_type": CardEnums.CardType.STRATEGY, "count": 1}]


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
			return CardUtils.is_strategy(card),
		tr("STR_EFF_EBP02_003_PROMPT"),
		true)

	if not selected.is_empty():
		if ctx.owner.monster_zone < 8:
			await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, ctx.owner.monster_zone + 1)
