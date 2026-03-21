extends CardEffect

## EBP01-054: Destoroyah Flying Form - Battle Rank 6 (Blue)
## <Evolution8> <Destoroyah> At the beginning of your main phase, you may play a rank 8
## or lower <Destoroyah> battle card from your deck by placing it on top of this card.
## <Enter> If this card was played through evolution, draw 2 cards, then discard 2 cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["evolution", "draws_cards"]


func get_phase_start_filter() -> Dictionary:
	return {"phase": CardEnums.GamePhase.MAIN, "own_turn": true}


func on_phase_start(ctx: EffectContext, phase: CardEnums.GamePhase) -> void:
	if phase != CardEnums.GamePhase.MAIN:
		return
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zone_idx)


func on_enter(ctx: EffectContext) -> void:
	if not ctx.card_data.get("played_through_evolution", false):
		return

	ctx.owner.draw_cards(2)
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, ctx.owner.hand.size() - 2)
