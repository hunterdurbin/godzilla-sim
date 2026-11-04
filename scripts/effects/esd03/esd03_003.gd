extends CardEffect

## ESD03-003: Godzilla(2026) - Monster Rank 3 (Red)
## <Enter> Reveal the top card of your deck. If it's a monster card, add it to
## your hand. Otherwise, discard it.
## <Opponent's Turn> <Dominate> At the beginning of the counter phase,
## <Destroy> all of your opponent's rank 6 or lower battle cards in the same
## column as this card.
##
## Tested: Yes
## Known issues: None
## Edge cases: Empty deck → the enter effect does nothing. Dominate is checked
##   when the counter phase begins.
## Rules: None
## Interactions: None
## Implementation notes: <Dominate> = ctx.is_dominate(). The counter-phase
##   sweep mirrors EBP01-006 (rank cap 6 instead of 5).

const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false},
}

const MAX_RANK := 6


func get_bot_tags() -> Array[String]:
	return ["draws_cards", "destroys_zone", "column_dependent_battle"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return MAX_RANK


func on_enter(ctx: EffectContext) -> void:
	var revealed := await ctx.effect_handler.reveal_deck_top(ctx.owner.player_id, 1)
	if revealed.is_empty():
		return
	if CardUtils.is_monster(revealed[0]):
		ctx.effect_handler.add_cards_to_hand(ctx.owner.player_id, revealed)
	else:
		ctx.effect_handler.discard_cards(ctx.owner.player_id, revealed)


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	if not ctx.is_dominate():
		return
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	var zones_to_destroy: Array[int] = []
	for zi in ctx.get_opponent_column_zones_with_cards(monster_zone_idx):
		var zone_card := ctx.opponent.get_zone_top_card(zi)
		if ctx.field_rank(zone_card, ctx.opponent.player_id) <= MAX_RANK:
			zones_to_destroy.append(zi)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
