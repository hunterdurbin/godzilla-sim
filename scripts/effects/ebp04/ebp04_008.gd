extends CardEffect
## EBP04-008: Godzilla (2001) - Monster Rank 3 (Red)
## <Burst II>
## <Awakening 8> At the beginning of your counter phase, your opponent discards
## until they have 3 cards in hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand"]


func get_burst_rank() -> int:
	return 2


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if not ctx.is_awakening(8):
		return
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 3)
