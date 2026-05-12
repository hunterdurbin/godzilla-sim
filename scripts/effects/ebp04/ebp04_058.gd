extends CardEffect
## EBP04-058: Servum - Battle Rank 3 (Green)
## <Awakening 4> If this card is in a zone adjacent to your monster card, this card
## gains +3000 counter power. (Active if your monster card is in zone 4 or beyond.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "zone_dependent"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if not ctx.is_awakening(4):
		return 0
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone < 0:
		return 0
	var monster_idx: int = ctx.owner.monster_zone - 1
	if my_zone in get_adjacent_zones(monster_idx):
		return 3000
	return 0
