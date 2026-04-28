extends CardEffect
# Yakusugi (Strategy R3)
# <Base>
# <Your Turn> Counter start: evolve 1 of your R4 or lower battle cards with Evolution.
#
# Tested: No, Looks good at glance
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["evolves"]


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	return owner.has_zone_matching(func(c: Dictionary) -> bool:
		return CardUtils.rank_at_most(c, 4) and c.get("evolution_rank", -1) >= 0)


func is_base_strategy() -> bool:
	return true


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	# Find zones with R4 or lower battle cards that have Evolution
	var valid_zones: Array[int] = ctx.owner.get_zone_top_indices_matching(func(c: Dictionary) -> bool:
		return ctx.field_rank(c, ctx.owner.player_id) <= 4 and c.get("evolution_rank", -1) >= 0)

	if valid_zones.is_empty():
		return

	var chosen := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		tr("STR_EFF_EBP03_075_PROMPT"), true)
	if chosen < 0:
		return

	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, chosen)
