extends CardEffect

## EBP01-026: Jet Jaguar(2023) - Battle Rank 7
## At the beginning of your counter phase, you may place 1 card with both <《Gigan》> and
## <《Fest》> from your discard pile under this card.
## If there is a card under this card, this card gains +5000 counter power.
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
	return ["plays_from_discard", "boosts_cp"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	# Search discard for a card with both Gigan and Fest traits
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.has_trait(card, CardEnums.CardTrait.GIGAN) \
				and CardUtils.has_trait(card, CardEnums.CardTrait.FEST),
		tr("STR_EFF_EBP01_026_PROMPT")
	)

	if not selected.is_empty():
		# Place under this card (append to end of zone stack)
		ctx.owner.zones[zone_idx].append(selected)
		ctx.owner.zones_changed.emit()


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return 0
	# Check if there's a card under this card (stack size > 1)
	if ctx.owner.get_zone_stack(zone_idx).size() > 1:
		return 5000
	return 0
