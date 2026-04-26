extends CardEffect
## EBP04-086: Mechagodzilla City - Strategy Rank 4 (Green)
## <Base>
## <Your Turn> At the beginning of the counter phase, for each 5 green battle
## cards in your discard pile, play 1 [Valkyrie] battle card from your discard
## pile.
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
	return ["plays_from_discard"]


func is_base_strategy() -> bool:
	return true


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var green_count: int = 0
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card) and CardUtils.has_color(card, CardEnums.CardColor.GREEN):
			green_count += 1

	var plays: int = green_count / 5
	if plays == 0:
		return

	for _i in range(plays):
		var found := await ctx.effect_handler.search_discard(
			ctx.owner.player_id,
			func(card: Dictionary) -> bool:
				return CardUtils.has_trait(card, CardEnums.CardTrait.VALKYRIE),
			tr("STR_EFF_EBP04_086_PROMPT"),
			false)
		if found.is_empty():
			break
		await ctx.effect_handler.play_from_discard(ctx.owner.player_id, found)
