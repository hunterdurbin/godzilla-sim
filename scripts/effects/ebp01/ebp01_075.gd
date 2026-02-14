extends CardEffect

## EBP01-075: Godzilla, King of the Monsters - Battle Rank 8 (White)
## This card gains +3000 counter power for each of your monster card's <Rage>.
## If your monster card has 3 or more <Rage>, and this card is in zones 1-5, this card
## cannot be <Destroy> by your opponent's effects.
## <Awakening8> You can play this card with its rank reduced by 4.
## (Active if your monster card is in zone 8. After being played, this card is rank 8.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_counter_power_modifier(ctx: EffectContext) -> int:
	return 3000 * ctx.owner.rage


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	# Only modifies self
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	# Awakening8: monster must be in zone 8
	if ctx.owner.monster_zone >= 8:
		return -4
	return 0


func can_be_destroyed(ctx: EffectContext) -> bool:
	# If monster has 3+ rage and this card is in zones 1-5, cannot be destroyed by opponent
	if ctx.owner.rage >= 3:
		var zone_idx := find_zone_of_card(ctx)
		if zone_idx >= 0 and zone_idx <= 4:
			return false
	return true


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]
