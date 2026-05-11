extends CardEffect

## EFC01-006: King Ghidorah's Defense - Strategy Rank 3 (White)
## <Opponent's Turn> If the opponent has 2 or less battle cards in their zones, none of
## the battle cards in your zones can be destroyed by your opponent's effects.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"protects_card_from_destruction": {"own_turn": false, "caused_by_opponent": true},
}


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func protects_card_from_destruction(ctx: EffectContext, card_data: Dictionary, _zone_idx: int) -> bool:
	# Turn / cause-by-opponent gating handled by TRIGGER_FILTERS.
	# Count opponent's battle cards in zones — only protect when ≤2.
	var count: int = ctx.opponent.count_zones_matching(CardUtils.is_battle)
	if count > 2:
		return false
	return CardUtils.is_battle(card_data)
