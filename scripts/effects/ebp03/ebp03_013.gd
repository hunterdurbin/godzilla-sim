extends CardEffect

## EBP03-013: Godzilla(1995) - Monster Rank 4 (Blue)
## <Enter> For the rest of the game, you have 3 strategy card zones.
## (It remains 3 even if this leaves play.)
## <Opponent's Turn> At the beginning of the counter phase, if there are no cards in
## your strategy zones, you lose the game.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false},
}


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func on_enter(ctx: EffectContext) -> void:
	# Expand strategy zones to 3 (permanent for rest of game)
	if ctx.owner.strategy_zones.size() < 3:
		ctx.owner.strategy_zones.resize(3)
		ctx.owner.strategy_zones[2] = {}
		ctx.owner.strategy_zone_turn_placed.resize(3)
		ctx.owner.strategy_zone_turn_placed[2] = 0
		ctx.owner.strategy_zone_stacks.resize(3)
		ctx.owner.strategy_zone_stacks[2] = []
		ctx.owner.strategy_zones_changed.emit()


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	# Check if any strategy cards are in play
	var has_strategy: bool = false
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty():
			has_strategy = true
			break

	if not has_strategy:
		# You lose the game
		var opponent_id: int = 1 - ctx.owner.player_id
		ctx.game_state.game_over.emit(opponent_id, "STR_LOG_REASON_NO_STRATEGIES")
