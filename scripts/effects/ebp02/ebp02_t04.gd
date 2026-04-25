extends CardEffect

## EBP02-T04: Chibi Godzilla 2nd Form - Token Battle Rank 8 (White)
## At the beginning of your end phase, <Destroy> this card and play 1 battle card
## named "Chibi Godzilla" from your discard pile.
## (Tokens cannot be added to the deck. They are banished when removed from zones.)
##
## Tested: No
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

	# Destroy self (token gets banished via banish_or_discard)
	var stack: Array = ctx.owner.clear_zone(zone_idx)
	EffectHandler.banish_or_discard(ctx.owner, stack)
	ctx.owner.zones_changed.emit()
	ctx.owner.discard_changed.emit()

	# Search discard for a battle card named "Chibi Godzilla"
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return card.get("name", "") == "Chibi Godzilla",
		tr("STR_EFF_EBP02_T04_DISCARD_PROMPT"))

	if selected.is_empty():
		return

	# Let the player choose any zone to play the Chibi Godzilla
	var valid_zones: Array[int] = []
	for i in range(8):
		if i != ctx.owner.monster_zone - 1:
			valid_zones.append(i)
	var target_zone: int = await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, valid_zones,
		tr("STR_EFF_EBP02_T04_PROMPT"))
	if target_zone < 0:
		return

	# Handle overload if zone occupied
	if ctx.owner.zone_has_cards(target_zone):
		var destroyed_stack: Array = ctx.owner.clear_zone(target_zone)
		EffectHandler.banish_or_discard(ctx.owner, destroyed_stack)
		ctx.owner.discard_changed.emit()

	ctx.owner.push_zone_card(target_zone, selected)
	ctx.owner.zones_changed.emit()
	await ctx.effect_handler.trigger_enter(ctx.owner.player_id, selected, true)
