extends CardEffect

## EBP01-020: Anguirus(1968) - Battle Rank 3
## If this card is in zone 8, whenever your monster card invades, you may reduce its
## <Rage> by 1 to search your deck for up to 1 monster card with <Burst> , reveal it,
## add it to your hand, then shuffle your deck.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_invasion_observed": {"own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["searches_deck", "zone_dependent"]


func get_bot_preferred_zones() -> Array[int]:
	return [7]  # zone 8 (0-indexed)


func on_invasion_observed(ctx: EffectContext, _invading_player_id: int, _from_zone: int, _to_zone: int) -> void:
	if find_zone_of_card(ctx) != 7:
		return
	if not ctx.has_rage():
		return

	# "you may" — ask the player
	var choice: int = await ctx.effect_handler.select_choice(
		ctx.owner.player_id,
		[tr("STR_EFF_BTN_YES"), tr("STR_EFF_BTN_NO")],
		tr("STR_EFF_EBP01_020_PROMPT")
	)
	if choice != 0:
		return

	# Cost: reduce rage by 1
	await ctx.effect_handler.reduce_rage(ctx.owner.player_id, 1)

	var selected := await ctx.effect_handler.search_deck(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if not CardUtils.is_monster(card):
				return false
			var effect := ctx.effect_handler.get_effect(card)
			return effect != null and effect.get_burst_rank() >= 0,
		tr("STR_EFF_EBP01_020_SEARCH")
	)
	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
