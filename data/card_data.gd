extends Node
## Autoload singleton: card definitions and deck builders


# --- Monster Decks ---

var KAIJU_MONSTERS: Array[Dictionary] = [
	{
		"id": "godzilla_1", "name": "Godzilla", "card_type": CardEnums.CardType.MONSTER,
		"rank": 1, "color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.KAIJU,
		"threat_level": 10000, "invasion_icon": 0, "description": "King of the Monsters awakens."
	},
	{
		"id": "godzilla_2", "name": "Godzilla - Evolved", "card_type": CardEnums.CardType.MONSTER,
		"rank": 2, "color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.KAIJU,
		"threat_level": 15000, "invasion_icon": 0, "description": "Power grows with rage."
	},
	{
		"id": "godzilla_3", "name": "Godzilla - Awakened", "card_type": CardEnums.CardType.MONSTER,
		"rank": 3, "color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.KAIJU,
		"threat_level": 20000, "invasion_icon": 0, "description": "Atomic breath charges."
	},
	{
		"id": "godzilla_4", "name": "Godzilla - Final Form", "card_type": CardEnums.CardType.MONSTER,
		"rank": 4, "color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.KAIJU,
		"threat_level": 30000, "invasion_icon": 0, "description": "Unstoppable force of nature."
	},
]

var MECHA_MONSTERS: Array[Dictionary] = [
	{
		"id": "mechagodzilla_1", "name": "Mechagodzilla", "card_type": CardEnums.CardType.MONSTER,
		"rank": 1, "color": CardEnums.CardColor.BLUE, "trait": CardEnums.CardTrait.MECHA,
		"threat_level": 10000, "invasion_icon": 0, "description": "Mechanical titan awakens."
	},
	{
		"id": "mechagodzilla_2", "name": "Mechagodzilla Mk-II", "card_type": CardEnums.CardType.MONSTER,
		"rank": 2, "color": CardEnums.CardColor.BLUE, "trait": CardEnums.CardTrait.MECHA,
		"threat_level": 15000, "invasion_icon": 0, "description": "Upgraded armaments online."
	},
	{
		"id": "mechagodzilla_3", "name": "Mechagodzilla Mk-III", "card_type": CardEnums.CardType.MONSTER,
		"rank": 3, "color": CardEnums.CardColor.BLUE, "trait": CardEnums.CardTrait.MECHA,
		"threat_level": 20000, "invasion_icon": 0, "description": "Plasma cannons armed."
	},
	{
		"id": "mechagodzilla_4", "name": "Mechagodzilla - Apex", "card_type": CardEnums.CardType.MONSTER,
		"rank": 4, "color": CardEnums.CardColor.BLUE, "trait": CardEnums.CardTrait.MECHA,
		"threat_level": 30000, "invasion_icon": 0, "description": "Ultimate weapon deployed."
	},
]


# --- Deck Building ---

func get_monster_deck(trait_type: CardEnums.CardTrait) -> Array[Dictionary]:
	match trait_type:
		CardEnums.CardTrait.KAIJU:
			return KAIJU_MONSTERS.duplicate(true)
		CardEnums.CardTrait.MECHA:
			return MECHA_MONSTERS.duplicate(true)
		_:
			push_error("CardData: No monster deck for trait %s" % trait_type)
			return []


func get_main_deck(deck_id: int) -> Array[Dictionary]:
	var deck: Array[Dictionary] = []

	# 10x Rank 1 battle (CP 2000, inv 1)
	for i in range(10):
		deck.append({
			"id": "infantry_%d_%d" % [deck_id, i], "name": "Infantry Squad",
			"card_type": CardEnums.CardType.BATTLE, "rank": 1,
			"color": CardEnums.CardColor.WHITE, "trait": CardEnums.CardTrait.KAIJU,
			"counter_power": 2000, "invasion_icon": 1,
			"description": "Basic defense unit."
		})

	# 8x Rank 2 battle (CP 3000, inv 1)
	for i in range(8):
		deck.append({
			"id": "tank_%d_%d" % [deck_id, i], "name": "Tank Battalion",
			"card_type": CardEnums.CardType.BATTLE, "rank": 2,
			"color": CardEnums.CardColor.BLUE, "trait": CardEnums.CardTrait.MECHA,
			"counter_power": 3000, "invasion_icon": 1,
			"description": "Armored division."
		})

	# 7x Rank 3 battle (CP 4000, inv 1)
	for i in range(7):
		deck.append({
			"id": "artillery_%d_%d" % [deck_id, i], "name": "Artillery Battery",
			"card_type": CardEnums.CardType.BATTLE, "rank": 3,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.KAIJU,
			"counter_power": 4000, "invasion_icon": 1,
			"description": "Long range bombardment."
		})

	# 4x Rank 4 battle (CP 5000, inv 2)
	for i in range(4):
		deck.append({
			"id": "maser_%d_%d" % [deck_id, i], "name": "Maser Cannon",
			"card_type": CardEnums.CardType.BATTLE, "rank": 4,
			"color": CardEnums.CardColor.GREEN, "trait": CardEnums.CardTrait.MECHA,
			"counter_power": 5000, "invasion_icon": 2,
			"description": "Energy weapon platform."
		})

	# 5x Rank 5 battle (CP 7000, inv 1)
	for i in range(5):
		deck.append({
			"id": "super_x_%d_%d" % [deck_id, i], "name": "Super X",
			"card_type": CardEnums.CardType.BATTLE, "rank": 5,
			"color": CardEnums.CardColor.BLUE, "trait": CardEnums.CardTrait.MECHA,
			"counter_power": 7000, "invasion_icon": 1,
			"description": "Advanced aerial weapon."
		})

	# 3x Rank 6 battle (CP 9000, inv 2)
	for i in range(3):
		deck.append({
			"id": "orbital_%d_%d" % [deck_id, i], "name": "Orbital Strike",
			"card_type": CardEnums.CardType.BATTLE, "rank": 6,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.KAIJU,
			"counter_power": 9000, "invasion_icon": 2,
			"description": "Satellite weapon system."
		})

	# 6x Strategy rank 1-3 (inv 1)
	for i in range(6):
		deck.append({
			"id": "strat_low_%d_%d" % [deck_id, i], "name": "Tactical Retreat",
			"card_type": CardEnums.CardType.STRATEGY, "rank": (i % 3) + 1,
			"color": CardEnums.CardColor.WHITE, "trait": CardEnums.CardTrait.KAIJU,
			"invasion_icon": 1, "description": "No effect (v1)."
		})

	# 4x Strategy rank 4-6 (inv 1)
	for i in range(4):
		deck.append({
			"id": "strat_mid_%d_%d" % [deck_id, i], "name": "Emergency Protocol",
			"card_type": CardEnums.CardType.STRATEGY, "rank": (i % 3) + 4,
			"color": CardEnums.CardColor.GREEN, "trait": CardEnums.CardTrait.MECHA,
			"invasion_icon": 1, "description": "No effect (v1)."
		})

	# 3x Strategy rank 4-6 (inv 2)
	for i in range(3):
		deck.append({
			"id": "strat_high_%d_%d" % [deck_id, i], "name": "Omega Protocol",
			"card_type": CardEnums.CardType.STRATEGY, "rank": (i % 3) + 4,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.KAIJU,
			"invasion_icon": 2, "description": "No effect (v1)."
		})

	# Total: 10+8+7+4+5+3+6+4+3 = 50 cards
	# Invasion icon 2 count: 4+3+3 = 10 (matches deck constraint)
	return deck


func get_card_by_id(id: String) -> Dictionary:
	for card in KAIJU_MONSTERS + MECHA_MONSTERS:
		if card.get("id") == id:
			return card
	return {}
