extends CardEffect
## EBP04-027: Gigan (2004) - Monster Rank 1 (Green)
## This card cannot advance nor invade.
## <Your Turn> At the beginning of your main phase, you may discard 1 card with <Step 2>
## from your hand. If you do, counter this card.
## <Opponent’s Turn> At the beginning of the main phase, your opponent may discard 1
## card with <Step 2> from their hand. If they do, counter this card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.MAIN},
}


func get_bot_tags() -> Array[String]:
	return []


func can_monster_advance(_ctx: EffectContext) -> bool:
	return false


func can_monster_invade(_ctx: EffectContext) -> bool:
	return false


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
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

	# "This card is countered" — Gigan (ctx.owner's monster) is the party whose
	# monster retreats and ranks up regardless of which player paid the cost.
	if ctx.effect_handler.action_handler:
		await ctx.effect_handler.force_counter(ctx.owner.player_id)
