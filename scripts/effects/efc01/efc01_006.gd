extends CardEffect

## EFC01-006: King Ghidorah's Defense - Strategy Rank 3 (White)
## <Opponent's Turn> If your opponent has 2 or fewer battle cards in zones,
## your battle cards cannot be destroyed by your opponent's effects.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func protects_card_from_destruction(ctx: EffectContext, card_data: Dictionary, _zone_idx: int) -> bool:
	# Only during opponent's turn
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return false
	# Count opponent's battle cards in zones
	var count: int = ctx.opponent.count_zones_matching(CardUtils.is_battle)
	if count > 2:
		return false
	# Protect all our battle cards
	return CardUtils.is_battle(card_data)
