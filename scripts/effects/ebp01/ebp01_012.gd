extends CardEffect

## EBP01-012: Godzilla(Fest Godzilla) - Monster Rank 2
## At the beginning of your end phase, if this card invaded this turn,
## advance your opponent's monster card by 1 zone.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.END, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["advances_opponent"]


func bot_can_fulfill_on_phase_start(_owner: PlayerState, opponent: PlayerState, _effect_handler = null) -> bool:
	return opponent.monster_zone < 8


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if not ctx.owner.has_invaded_this_turn:
		return
	if ctx.opponent.monster_zone < 8:
		await ctx.effect_handler.advance_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone + 1)
