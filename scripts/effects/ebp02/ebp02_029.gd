extends CardEffect

## EBP02-029: Biollante Plant Beast Form - Monster Rank 4 (Blue)
## <Opponent's Turn> At the beginning of the counter phase, for the rest of the turn,
## double the counter power of all of your opponent's battle cards in the same column
## as this card. (Refer to those battle card's counter power at the ability resolution timing.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "column_avoid_battle_cards"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_opponent_doubled_zones(ctx: EffectContext) -> Array[int]:
	# Only active from counter phase onward during opponent's turn (relative
	# to this card's controller).
	if ctx.is_own_turn():
		return []
	if ctx.game_state.current_phase < CardEnums.GamePhase.COUNTER:
		return []
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	if monster_zone_idx < 0:
		return []
	var doubled: Array[int] = []
	for zi in get_opponent_column_zones(monster_zone_idx):
		var opp_card: Dictionary = ctx.opponent.get_zone_top_card(zi)
		if not opp_card.is_empty() and opp_card.get("counter_power", 0) > 0:
			doubled.append(zi)
	return doubled
