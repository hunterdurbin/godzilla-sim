extends CardEffect
# Multi-purpose Fighting System-3 R3
# <Enter> If there is a blue battle card in your zones, <Destroy> 1 of your opponent’s
# rank 5 or lower battle cards.
# <Opponent’s Turn> At the beginning of the counter phase, if there is a red battle
# card in your zones, <Destroy> 1 of your opponent’s rank 5 or lower battle cards in
# the same column as this card.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false},
}


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "column_dependent_monster_self"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.has_zone_matching(func(c: Dictionary) -> bool:
		return CardUtils.is_battle(c) and CardUtils.has_color(c, CardEnums.CardColor.BLUE))


func on_enter(ctx: EffectContext) -> void:
	if not _has_color_battle_in_zones(ctx, CardEnums.CardColor.BLUE):
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card): return ctx.field_rank(card, ctx.opponent.player_id) <= 5,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 5)


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if not _has_color_battle_in_zones(ctx, CardEnums.CardColor.RED):
		return

	# Get opponent zones in same column as this monster
	var monster_idx: int = ctx.owner.monster_zone - 1
	var valid_zones: Array[int] = []
	for opp_zi in ctx.get_opponent_column_zones_with_cards(monster_idx):
		var opp_card := ctx.opponent.get_zone_top_card(opp_zi)
		if ctx.field_rank(opp_card, ctx.opponent.player_id) <= 5:
			valid_zones.append(opp_zi)

	if valid_zones.is_empty():
		return

	await ctx.effect_handler.destroy_chosen_zone(
		ctx.owner.player_id, ctx.opponent, valid_zones,
		tr("STR_EFF_EBP03_008_PROMPT"))


func _has_color_battle_in_zones(ctx: EffectContext, color: CardEnums.CardColor) -> bool:
	return ctx.owner.has_zone_matching(func(c: Dictionary) -> bool:
		return CardUtils.is_battle(c) and CardUtils.has_color(c, color))
