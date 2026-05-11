extends CardEffect

## EBP01-050: Mothra(larva)(1992) - Battle Rank 4 (Blue)
## <Evolution7> <《Mothra》> (At the beginning of your main phase, you may play a rank 7
## or lower <《Mothra》> battle card from your deck by placing it on top of this card.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.MAIN, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["evolution"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zone_idx)
