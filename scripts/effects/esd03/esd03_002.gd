extends CardEffect

## ESD03-002: Godzilla(2026) - Monster Rank 2 (Red)
## <Enter> <Destroy> all rank 3 or lower battle cards of each player.
##
## Tested: Yes
## Known issues: None
## Edge cases: Rank is the effective field rank (rank modifiers apply).
## Rules: None
## Interactions: Revenge triggers from both boards resolve after the sweep
##   (destroy_zones defers them per 10.4.3).
## Implementation notes: Owner's board is swept first, then the opponent's
##   (same order as ESD03-008).

const MAX_RANK := 3


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return MAX_RANK


func on_enter(ctx: EffectContext) -> void:
	var own_targets := _low_rank_zones(ctx, ctx.owner)
	var opp_targets := _low_rank_zones(ctx, ctx.opponent)
	if not own_targets.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.owner, own_targets)
	if not opp_targets.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, opp_targets)


func _low_rank_zones(ctx: EffectContext, player: PlayerState) -> Array[int]:
	var out: Array[int] = []
	for zi in player.get_battle_card_zone_indices():
		if ctx.field_rank(player.get_zone_top_card(zi), player.player_id) <= MAX_RANK:
			out.append(zi)
	return out
