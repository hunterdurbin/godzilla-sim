extends CardEffect

## EBP02-T03: Crystals - Token Battle Rank 1 (Green)
## All of your <SpaceGodzilla> monster cards in your zones gain +1000 threat level.
## (Tokens cannot be added to the deck. They are banished when removed from zones.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	# Only grants TL bonus if owner's current monster has the SpaceGodzilla trait
	var monster_traits: Array = ctx.owner.current_monster.get("traits", [])
	if CardEnums.CardTrait.SPACEGODZILLA in monster_traits:
		return 1000
	return 0
