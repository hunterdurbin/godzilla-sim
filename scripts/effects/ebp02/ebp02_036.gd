extends CardEffect

## EBP02-036: Godzilla(1994) - Battle Rank 7 (Blue)
## At the beginning of your end phase, if this card is in a zone adjacent to your
## monster card, 1 of your opponent's monster cards with 40,000 or less threat level
## retreats back by 1 zone.
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
	return ["weakens_opponent", "retreats_opponent"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var adjacent := get_adjacent_zones(monster_zone_idx)
	if zone_idx not in adjacent:
		return

	var opp_tl: int = ctx.effect_handler.get_effective_threat_level(ctx.opponent.player_id)
	if opp_tl <= 40000 and ctx.opponent.monster_zone > 1:
		await ctx.effect_handler.retreat_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone - 1)
