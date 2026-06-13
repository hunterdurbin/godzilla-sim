extends CardEffect
# The Battle at Fukuoka Tower (Strategy R4)
# <Base> When any monster card invades into zones 6–8, <Destroy> this card. (Cards with
# Base are not sent to the discard pile at the start phase.)
# <Opponent’s Turn> For each monster or battle card in your zones 1, 5, and 8, your
# monster card gains +5000 threat level.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "zone_dependent"]


func get_bot_preferred_zones() -> Array[int]:
	return [0, 4, 7]


func is_base_strategy() -> bool:
	return true


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.is_own_turn():
		return 0 # Opponent's turn only

	var bonus := 0
	# Zones 1, 5, 8 = indices 0, 4, 7
	var check_zones: Array[int] = [0, 4, 7]
	for zi in check_zones:
		# Check for battle card in zone
		if ctx.owner.zone_has_cards(zi):
			bonus += 5000
		# Check if own monster is in this zone
		if ctx.owner.monster_zone == zi + 1:
			bonus += 5000

	return bonus
