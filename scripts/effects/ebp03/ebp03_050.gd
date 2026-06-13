extends CardEffect
# Rainbow Mothra (Battle R7)
# <Enter> If you have a card with <Base> in play, an opponent’s monster card with
# 20,000 or less threat level retreats backward by 1 zone.
# <Evolution8> <《Mothra》> (At the beginning of your main phase, you may play a rank 8
# or lower <《Mothra》> battle card from your deck by placing it on top of this card.)
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.MAIN, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["evolution", "retreats_opponent"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return
	await ctx.effect_handler.perform_evolution(ctx.owner.player_id, zone_idx)


func on_enter(ctx: EffectContext) -> void:
	if not _has_base_in_play(ctx):
		return

	var opp_tl: int = ctx.opponent.current_monster.get("threat_level", 0) + ctx.opponent.rage * 5000
	opp_tl += ctx.effect_handler.get_threat_level_modifier(ctx.opponent.player_id)

	if opp_tl > 20000:
		return

	if ctx.opponent.monster_zone <= 1:
		return

	await ctx.effect_handler.retreat_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone - 1)


func _has_base_in_play(ctx: EffectContext) -> bool:
	for strategy in ctx.owner.strategy_zones:
		if not strategy.is_empty() and strategy.get("is_base", false):
			return true
	return false
