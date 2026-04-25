extends CardEffect
# Mechagodzilla(1975) (Battle R7)
# Counter start: may move this card to an unoccupied zone.
# If same column as opponent monster, +3000 CP.
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
	return ["boosts_cp", "column_dependent_monster"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var empty := ctx.owner.get_empty_zone_indices()
	if empty.is_empty():
		return

	var dest := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, empty,
		tr("STR_EFF_MOVE_TO_EMPTY_OR_SKIP"), true)
	if dest < 0:
		return

	var stack: Array = ctx.owner.zones[zone_idx]
	ctx.owner.zones[zone_idx] = []
	ctx.owner.zones[dest] = stack
	ctx.owner.zones_changed.emit()


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if _is_in_opponent_monster_column(ctx):
		return 3000
	return 0


func _is_in_opponent_monster_column(ctx: EffectContext) -> bool:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return false
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	return opp_monster_idx in get_opponent_column_zones(zone_idx)
