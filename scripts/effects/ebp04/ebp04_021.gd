extends CardEffect
## EBP04-021: Godzilla Aquatilius - Monster Rank 1 (Green)
## At the beginning of your counter phase, you may discard the top card of your
## deck. If that card is a green battle card, your opponent discards until they
## have 4 cards in hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand", "mill_self"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if ctx.owner.main_deck.is_empty():
		return

	var chosen: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id, [tr("STR_EFF_EBP04_021_CHOICE"), tr("STR_EFF_BTN_SKIP")],
		tr("STR_EFF_EBP04_021_PROMPT"))
	if chosen != 0:
		return

	var top_card := await ctx.mill_one()
	if top_card.is_empty():
		return

	var is_green_battle: bool = (
		CardUtils.is_battle(top_card) and
		CardUtils.has_color(top_card, CardEnums.CardColor.GREEN)
	)
	if is_green_battle:
		await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 4)
