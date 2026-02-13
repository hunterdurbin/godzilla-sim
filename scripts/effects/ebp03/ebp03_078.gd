extends CardEffect
# Megalon and Gigan: Villain Tag Team (Strategy R5)
# If opponent has 3+ battle cards in zones, Destroy leftmost and rightmost.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	# Find all occupied opponent zones (from left to right = zone 1 to 8 = index 0 to 7)
	var occupied: Array[int] = []
	for i in range(8):
		if not ctx.opponent.is_zone_empty(i):
			occupied.append(i)

	if occupied.size() < 3:
		return

	var leftmost: int = occupied[0]
	var rightmost: int = occupied[occupied.size() - 1]

	var zones_to_destroy: Array[int] = [leftmost, rightmost]
	await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
