extends CardEffect

## ESD04-001: Destoroyah Juvenile Form - Monster Rank 1 (Blue)
## <Overwhelm> At the beginning of your end phase, you may reveal 1 battle card
## from your hand and place it on the bottom of your deck. If you do, draw 1
## card.
##
## Tested: Yes
## Known issues: None
## Edge cases: Overwhelm is checked when the end phase begins (no prompt
##   otherwise).
## Rules: None
## Interactions: None
## Implementation notes: <Overwhelm> = ctx.is_overwhelm(). The reveal is the
##   put_card_on_bottom_of_deck log line (names the card for both players).


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.END, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func bot_can_fulfill_on_phase_start(owner: PlayerState, opponent: PlayerState, _effect_handler = null) -> bool:
	return owner.monster_zone >= opponent.monster_zone and owner.hand.any(CardUtils.is_battle)


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if not ctx.is_overwhelm():
		return
	var card := await ctx.effect_handler.take_hand_card(
		ctx.owner.player_id,
		CardUtils.is_battle,
		tr("STR_EFF_ESD04_001_PROMPT"),
		true)
	if card.is_empty():
		return
	ctx.effect_handler.put_card_on_bottom_of_deck(ctx.owner.player_id, card)
	ctx.owner.draw_cards(1)
