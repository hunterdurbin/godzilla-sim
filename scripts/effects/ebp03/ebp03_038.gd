extends CardEffect
# Multi-purpose Fighting System-3 (Battle R6)
# At the beginning of your counter phase, if your opponent has 2 or more <Rage> ,
# <Destroy> all of your battle cards in zones adjacent to this card.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["avoid_own_adjacent"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if ctx.opponent.rage < 2:
		return

	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var adjacent := get_adjacent_zones(zone_idx)
	var zones_to_destroy: Array[int] = []
	for adj_zi in adjacent:
		if ctx.owner.zone_has_cards(adj_zi):
			zones_to_destroy.append(adj_zi)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.owner, zones_to_destroy)
