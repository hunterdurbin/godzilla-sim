extends CardEffect

## ESD01-010: City of Tokyo - Battle Rank 6
## If your monster card has 2 or more <Rage>, your other battle card in zone 8
## gains +5000 counter power.
## <Awakening6> Your other battle card in zone 8 gains +5000 counter power.
## (Active if your monster card is in zone 6 or beyond.)
##
## NOTE: This card gives a bonus to OTHER cards in zone 8, not to itself.
## The modifier is applied via get_counter_power_modifier on the zone 8 card check.
## Since the effect system evaluates each card independently, this effect is handled
## by checking if a "City of Tokyo" is active when calculating zone 8 card CP.
## For now, this is implemented as a self-modifier that the EffectHandler can query.


func get_counter_power_modifier(ctx: EffectContext) -> int:
	# This card itself has 0 CP. The bonus goes to OTHER cards in zone 8.
	# We handle this by checking zone 8 cards and looking for City of Tokyo presence.
	# This requires the zone 8 card's effect to check for City of Tokyo.
	# For simplicity, we return 0 for self - the zone 8 bonus is complex to implement
	# without a "field effect" system. Marking as TODO for future enhancement.
	#
	# TODO: Implement field-effect system where cards can grant bonuses to other cards.
	return 0
