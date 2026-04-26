extends CardEffect

## EBP01-001: Godzilla(1954) - Monster Rank 1
## At the beginning of your counter phase, send the top card of your deck to your discard pile.
## If it is a monster card, increase this card's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["mill_self"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var card := ctx.mill_one()
	if card.is_empty():
		return

	var revealed: Array[Dictionary] = [card]
	await ctx.effect_handler.select_from_cards(
		ctx.owner.player_id, revealed, revealed,
		tr("STR_EFF_DISCARDED_PILE"))

	if CardUtils.is_monster(card):
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1, ctx.card_data.get("id", ""))
		ctx.effect_handler.log_message.emit(
			GameLog.effect_gained_rage_from_mill(ctx.owner.player_id, ctx.card_data.get("id", ""), ctx.owner.rage, card.get("id", ""))
		)
