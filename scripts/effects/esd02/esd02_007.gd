extends CardEffect

## ESD02-007: Mothra(larva)(1992) - Battle Rank 2
## <Evolution5> <《Mothra》> At the beginning of your main phase, you may search your deck
## for a rank 5 or lower <《Mothra》> battle card and play it by stacking it on top of
## this card. Search for 「Mothra(imago)(1992)」 rank 5 counter power 5000 and you may
## place it on top of this card)
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
