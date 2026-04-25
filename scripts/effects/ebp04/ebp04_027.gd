extends CardEffect
## EBP04-027: Gigan (2004) - Monster Rank 1 (Green)
## This card cannot advance nor invade.
## <Your Turn> At the beginning of your main phase, you may discard a <Invade 2>
## card from your hand. If you do so this card is countered.
## <Opponent's Turn> At the beginning of their main phase, your opponent may
## discard a <Invade 2> card from their hand. If they do so this card is
## countered.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return []


func can_monster_advance(_ctx: EffectContext) -> bool:
	return false


func can_monster_invade(_ctx: EffectContext) -> bool:
	return false


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.MAIN}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.MAIN:
		return

	var is_own_turn := ctx.is_own_turn()
	var acting_player: PlayerState = ctx.owner if is_own_turn else ctx.opponent
	var acting_player_id: int = acting_player.player_id

	var selected := await ctx.effect_handler.select_hand_card(
		acting_player_id,
		func(card: Dictionary) -> bool: return card.get("invasion_icon", 0) == 2,
		tr("STR_EFF_EBP04_027_PROMPT"),
		true)
	if selected.is_empty():
		return

	# Force counter this card
	if ctx.effect_handler.action_handler:
		await ctx.effect_handler.force_counter(ctx.owner.player_id)
