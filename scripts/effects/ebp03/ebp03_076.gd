extends CardEffect
# The Battle at Fukuoka Tower (Strategy R4)
# <Base>
# <Opponent's Turn> +5000 TL for each monster or battle card in your zones 1, 5, and 8.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func is_base_strategy() -> bool:
	return true


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.game_state.current_player_id == ctx.owner.player_id:
		return 0  # Opponent's turn only

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
