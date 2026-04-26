extends CardEffect

## EBP02-012: Godzilla(2016) Frozen - Battle Rank 4 (Red)
## If this card is in zone 8, whenever your strategy cards would be discarded from
## the strategy zone, you may place them under this card instead.
## <Awakening4> At the beginning of your main phase, if there are 2 or more cards
## under this card, counter your opponent's monster card.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.MAIN, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["zone_dependent"]


func get_bot_preferred_zones() -> Array[int]:
	return [7]  # zone 8 (0-indexed)


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.REPLACEMENT]


func can_intercept_strategy_discard(ctx: EffectContext) -> bool:
	# Only intercepts if this card is in zone 8 (index 7)
	var zone_idx := find_zone_of_card(ctx)
	return zone_idx == 7


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	# Awakening4: monster must be in zone 4+
	if not ctx.is_awakening(4):
		return
	# Need 2+ cards under this card
	var zone_idx := find_zone_of_card(ctx)
	var stack_size: int = ctx.owner.get_zone_stack(zone_idx).size()
	if stack_size < 3: # 1 (self) + 2 (under)
		return
	# Force counter the opponent's monster
	await ctx.effect_handler.force_counter(ctx.opponent.player_id)
