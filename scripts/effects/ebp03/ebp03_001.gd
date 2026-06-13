extends CardEffect
# Godzilla(2001) R1
# <Awakening4> At the beginning of your end phase, you may discard 1 rank 5 or higher
# battle card from your hand. If you do, this card advances 1 zone.
# <Awakening6> This card gains +5000 threat level.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.END, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["advances_self", "boosts_threat"]


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	if not owner.is_awakening(4) or owner.is_awakening(8):
		return false
	for card in owner.hand:
		if CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5):
			return true
	return false


func bot_can_fulfill_threat_level(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.is_awakening(6)


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if not ctx.is_awakening(4):
		return
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_battle(card) and CardUtils.rank_at_least(card, 5),
		tr("STR_EFF_EBP03_001_PROMPT"),
		true
	)
	if not selected.is_empty():
		if not ctx.is_awakening(8):
			await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, ctx.owner.monster_zone + 1)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.is_awakening(6):
		return 5000
	return 0
