extends CardEffect
# Godzilla(2001) R4
# <Burst3> (You can play this card from rank III. If you do, send this card to your
# discard pile at the beginning of your next end phase.)
# <Awakening8> At the beginning of your counter phase, you may discard 1 rank 5 or
# higher battle card from your hand. If you do, increase this card’s <Rage> by 3, then
# <Destroy> all of your opponent’s rank 7 or lower battle cards. (Active if this card
# is in zone 8.)
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 7


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	if not owner.is_awakening(8):
		return false
	for card in owner.hand:
		if CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5):
			return true
	return false


func get_burst_rank() -> int:
	return 3


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if not ctx.is_awakening(8):
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5),
		tr("STR_EFF_EBP03_005_PROMPT"),
		true
	)
	if not selected.is_empty():
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 3, ctx.card_data.get("id", ""))

		var zones_to_destroy: Array[int] = ctx.effect_handler.get_zones_in_rank_range(ctx.opponent.player_id, -1, 7)
		if not zones_to_destroy.is_empty():
			await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
