extends RefCounted

## Static builders for hand-built card dictionaries used by unit tests.
## Shapes mirror the templates in data/card_data.gd, limited to the fields the
## engine actually reads. No CardData autoload dependency — the gdUnit CLI
## replaces the main loop, so autoload singletons are unavailable in unit runs.


static func battle(rank: int = 1, counter_power: int = 5000, id: String = "T-BTL", traits: Array = [], invasion_icon: int = 1) -> Dictionary:
	return {
		"id": id,
		"name": "Test Battle %s" % id,
		"card_type": CardEnums.CardType.BATTLE,
		"rank": rank,
		"colors": [CardEnums.CardColor.RED],
		"traits": traits,
		"counter_power": counter_power,
		"invasion_icon": invasion_icon,
	}


static func strategy(rank: int = 1, id: String = "T-STR", invasion_icon: int = 0) -> Dictionary:
	return {
		"id": id,
		"name": "Test Strategy %s" % id,
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": rank,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [],
		"invasion_icon": invasion_icon,
	}


static func monster(rank: int = 1, threat_level: int = 5000, traits: Array = [CardEnums.CardTrait.GODZILLA], id: String = "T-MON", invasion_icon: int = 1) -> Dictionary:
	return {
		"id": id,
		"name": "Test Monster %s" % id,
		"card_type": CardEnums.CardType.MONSTER,
		"rank": rank,
		"colors": [CardEnums.CardColor.RED],
		"traits": traits,
		"threat_level": threat_level,
		"invasion_icon": invasion_icon,
	}


## A full rank I-IV monster line sharing one trait, for monster_deck fixtures.
static func monster_line(traits: Array = [CardEnums.CardTrait.GODZILLA], id_prefix: String = "T-MON") -> Array[Dictionary]:
	var line: Array[Dictionary] = []
	for rank in range(1, 5):
		line.append(monster(rank, 4000 + rank * 2000, traits, "%s-R%d" % [id_prefix, rank]))
	return line
