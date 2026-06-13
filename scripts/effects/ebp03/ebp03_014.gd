extends CardEffect
# Godzilla(2002) R1
# At the beginning of your end phase, you may discard 1 battle card from your hand. If
# you do, draw 1 card.
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
	return ["draws_cards"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_battle(card),
		tr("STR_EFF_EBP03_014_PROMPT"),
		true
	)
	if not selected.is_empty():
		ctx.owner.draw_cards(1)
