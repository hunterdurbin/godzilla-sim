extends CardEffect
## EBP04-047: Monster X - Battle Rank 5 (Blue)
## This card’s counter power X is equal to 3000 multiplied by the number of different
## colors among other battle cards in your zones. (White also counts as a color.)
## <Evolution 8> 《Kaizer Ghidorah》 (At the beginning of your main phase, you may play a
## rank 8 or lower 《Kaizer Ghidorah》 battle card from your deck by placing it on top of
## this card.)
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
	return ["boosts_cp", "evolution"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return
	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zone_idx)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	# Rule says "other battle cards in your zones" — exclude self's zone.
	var self_zone: int = find_zone_of_card(ctx)
	var others: Array[Dictionary] = []
	for i in range(8):
		if i == self_zone:
			continue
		var top: Dictionary = ctx.owner.get_zone_top_card(i)
		if not top.is_empty() and CardUtils.is_battle(top):
			others.append(top)
	return CardUtils.count_distinct_colors(others) * 3000
