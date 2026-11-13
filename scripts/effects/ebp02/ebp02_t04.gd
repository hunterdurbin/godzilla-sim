extends CardEffect

## EBP02-T04: Chibi Godzilla 2nd Form - Token Battle Rank 8 (White)
## At the beginning of your end phase, <Destroy> this card and play 1 battle card
## named "Chibi Godzilla" from your discard pile.
## (Tokens cannot be added to the deck. They are banished when removed from zones.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.END, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	# <Destroy> this card (a token is banished, not discarded).
	await ctx.effect_handler.destroy_zones(ctx.owner, [zone_idx])

	# Search discard for a battle card named "Chibi Godzilla"
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("name", "") == "Chibi Godzilla",
		tr("STR_EFF_EBP02_T04_DISCARD_PROMPT"),
		false)

	if selected.is_empty():
		return

	# Let the player choose any zone to play the Chibi Godzilla
	var valid_zones: Array[int] = []
	for i in range(8):
		if i != ctx.owner.monster_zone - 1:
			valid_zones.append(i)
	var target_zone: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		tr("STR_EFF_EBP02_T04_PROMPT"), false, CardUtils.base_id(selected))
	if target_zone < 0:
		return

	# The engine overloads an occupied zone (11.5) and fires <Enter>.
	await ctx.effect_handler.play_from_discard(ctx.owner.player_id, selected, target_zone)
