extends CardEffect

## ESC01-003: Godzilla(2016) 4th Form - Battle Rank 4 (Red)
## <Enter> If this card is in zone 8 and your monster card invaded this turn,
## you may discard 1 strategy card from your hand. If you do, advance your
## monster card by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: "Advance" does not count as an invasion (no <When Invading>,
## has_invaded_this_turn untouched).
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_self", "zone_dependent"]


func get_bot_preferred_zones() -> Array[int]:
	return [7]


func get_bot_max_advance_zone(owner: PlayerState, _opponent: PlayerState) -> int:
	return mini(owner.monster_zone + 1, 8)


func get_bot_advance_reliability(owner: PlayerState, _opponent: PlayerState) -> int:
	if not owner.has_invaded_this_turn:
		return 0
	for card in owner.hand:
		if CardUtils.is_strategy(card):
			return 90
	return 0


func get_bot_effect_costs() -> Array[Dictionary]:
	return [{"card_type": CardEnums.CardType.STRATEGY, "count": 1}]


func on_enter(ctx: EffectContext) -> void:
	# Zone 8 is index 7
	if find_zone_of_card(ctx) != 7:
		return
	if not ctx.owner.has_invaded_this_turn:
		return
	if ctx.owner.monster_zone >= 8:
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_strategy(card),
		tr("STR_EFF_ESC01_003_PROMPT"),
		true
	)
	if selected.is_empty():
		return

	await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, ctx.owner.monster_zone + 1)
