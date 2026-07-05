extends CardEffect
## EBP04-031: Monster X - Monster Rank 1 (Red, Blue, Green)
## This card’s threat level X is equal to 3000 times the number of different colors
## among battle cards in your zones. If your opponent’s zones have 1 or fewer battle
## cards, this card cannot be countered.
## <Resonance> Red/Blue/Green
## ・Battle cards must be 《Final Wars》 only.
## (Red, blue, green, and white may be mixed, but your monster deck and main deck must
## be constructed to satisfy the above conditions.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Threat level X is a variable BASE stat
##   (get_variable_threat_level), not a modifier — shows as "Base threat" in
##   breakdowns.


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_variable_threat_level(ctx: EffectContext) -> int:
	return _count_zone_colors(ctx) * 3000


func prevents_counter(ctx: EffectContext, _total_cp: int) -> bool:
	# "If the opponent has 1 or less battle cards in their zones, they cannot
	# counter this." Counter is fully prevented — opponent's monster doesn't
	# retreat (would be the EBP02-027 immunity behavior).
	var battle_count: int = ctx.opponent.get_zone_top_cards_matching(
		func(c: Dictionary) -> bool: return CardUtils.is_battle(c)).size()
	return battle_count <= 1


func _count_zone_colors(ctx: EffectContext) -> int:
	var colors: Array[int] = []
	var battle_tops: Array[Dictionary] = ctx.owner.get_zone_top_cards_matching(
		func(c: Dictionary) -> bool: return CardUtils.is_battle(c))
	for zone_card in battle_tops:
		for c: int in zone_card.get("colors", []):
			if c not in colors:
				colors.append(c)
	return colors.size()
