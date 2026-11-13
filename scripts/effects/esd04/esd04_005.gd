extends CardEffect

## ESD04-005: Godzilla(1995) - Battle Rank 7 (Blue)
## <Opponent's Turn> At the beginning of the counter phase, if you have no
## strategy cards in play, <Destroy> all battle cards in your zones. (This
## card is also destroyed.)
##
## Tested: Yes
## Known issues: None
## Edge cases: The strategy check happens at resolution, so an earlier
##   standby effect in the same batch that puts a strategy into play (or
##   removes one) is respected.
## Rules: 10.4.3 — revenge triggers from the swept cards resolve after the
##   whole batch is destroyed (destroy_zones defers them).
## Interactions: None
## Implementation notes: No phase_start_applies gate — this is an ordinary
##   board-state condition (see scripts/effects/README.md).

const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false},
}


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if ctx.owner.has_any_strategy_in_play():
		return
	var zones := ctx.owner.get_battle_card_zone_indices()
	if not zones.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.owner, zones)
