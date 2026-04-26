extends CardEffect
## EBP04-031: Monster X - Monster Rank 1 (Red, Blue, Green)
## This card's X Threat increases by +3000 for each color of battle card in
## your zones. In addition, if the opponent has 1 or less battle cards in
## their zones, they cannot counter this.
## <Resonance> Red, Blue, Green.
## - You may only use Battle Cards with <Final Wars>.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
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
