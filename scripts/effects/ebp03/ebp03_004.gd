extends CardEffect
# Godzilla(2001) - Monster Rank 4 (Red)
# When this card invades, you may send the top card of your deck to your discard pile
# instead of discarding a card from your hand.
# <Opponent’s Turn> <Awakening4> This card’s <Rage> cannot be reduced by your
# opponent’s effects. (Active if this is in zone 4 or beyond.)
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_self"]


func can_replace_invasion_cost(_ctx: EffectContext) -> bool:
	return true


func prevents_rage_reduction(ctx: EffectContext) -> bool:
	# <Opponent's Turn> <Awakening4>: Rage cannot be reduced by opponent's effects
	if ctx.is_own_turn():
		return false # Only active on opponent's turn
	if not ctx.is_awakening(4):
		return false # Awakening4 not active
	return true
