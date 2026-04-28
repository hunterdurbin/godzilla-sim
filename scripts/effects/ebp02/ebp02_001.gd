extends CardEffect

## EBP02-001: Giant Unknown Creature - Monster Rank 1 (Red)
## <Opponent's Turn> At the beginning of the counter phase, you may discard 1 strategy
## card from your hand to increase this card's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false},
}


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.is_strategy(card),
		tr("STR_EFF_EBP02_001_PROMPT"),
		true)

	if not selected.is_empty():
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1, ctx.card_data.get("id", ""))
