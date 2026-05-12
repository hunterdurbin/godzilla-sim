extends CardEffect
## EBP04-001: Godzilla(2004) - Monster Rank 1 (Red)
## <Opponent’s Turn> At the beginning of the counter phase, if your opponent has no
## battle cards in the same column as this card, increase this card’s <Rage> by 1.
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
	if not ctx.get_opponent_column_zones_with_cards(ctx.owner.monster_zone - 1).is_empty():
		return
	await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1, ctx.card_data.get("id", ""))
