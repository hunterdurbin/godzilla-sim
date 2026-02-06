extends Node
## Autoload singleton: card definitions and deck builders

# Card template registry - maps card numbers to their base data (no copy-specific IDs)
var CARD_TEMPLATES: Dictionary = {}


func _ready() -> void:
	_build_card_templates()


func _build_card_templates() -> void:
	# Index all monster deck cards by their ID
	for card in KAIJU_MONSTERS + MECHA_MONSTERS + ESD01_MONSTERS:
		CARD_TEMPLATES[card["id"]] = card.duplicate()

	# ESD01 Main Deck card templates (base data without copy IDs)
	CARD_TEMPLATES["ESD01-005"] = {
		"name": "Godzilla (2023)", "card_type": CardEnums.CardType.MONSTER, "rank": 2,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"threat_level": 12000, "invasion_icon": 1,
		"description": "[Burst I] You can play this card from rank I. If you do, send this card to your discard pile at the beginning of your next end phase.\n[Enter] Your opponent discards cards until they have 4 cards remaining in their hand."
	}
	CARD_TEMPLATES["ESD01-006"] = {
		"name": "Godzilla (2023)", "card_type": CardEnums.CardType.MONSTER, "rank": 3,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"threat_level": 23000, "invasion_icon": 1,
		"description": "[Burst II] You can play this card from rank II. If you do, send this card to your discard pile at the beginning of your next end phase.\n[Enter] [Destroy] 1 of your opponents rank 4 or lower battle cards."
	}
	CARD_TEMPLATES["ESD01-007"] = {
		"name": "Godzilla (2023)", "card_type": CardEnums.CardType.MONSTER, "rank": 4,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"threat_level": 38000, "invasion_icon": 2,
		"description": "[Burst III] You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.\n[Enter] [Destroy] all of your opponents battle cards in the same column as this card."
	}
	CARD_TEMPLATES["ESD01-008"] = {
		"name": "Shinseimaru", "card_type": CardEnums.CardType.BATTLE, "rank": 2,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"counter_power": 2000, "invasion_icon": 1,
		"description": "(Battle cards in your hand can be played if their rank is equal to or lower than the number in the zone where the opponent's monster card is.)"
	}
	CARD_TEMPLATES["ESD01-009"] = {
		"name": "Reinforcements", "card_type": CardEnums.CardType.BATTLE, "rank": 4,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"counter_power": 2000, "invasion_icon": 1,
		"description": "[Awakening 4] This card gains +3000 counter power. (Active if your monster card is in zone 4 or beyond.)"
	}
	CARD_TEMPLATES["ESD01-010"] = {
		"name": "City of Tokyo", "card_type": CardEnums.CardType.BATTLE, "rank": 6,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"counter_power": 0, "invasion_icon": 1,
		"description": "If your monster card has 2 or more [Rage], your other battle card in zone 8 gains +5000 counter power.\n[Awakening 6] Your other battle card in zone 8 gains +5000 counter power."
	}
	CARD_TEMPLATES["ESD01-011"] = {
		"name": "Godzilla (2023)", "card_type": CardEnums.CardType.BATTLE, "rank": 5,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"counter_power": 3000, "invasion_icon": 1,
		"description": "[Enter] If your monster card has 2 or more [Rage], reduce your opponent's [Rage] by 1.\nWhen this card is [Destroy], place this card on the bottom of your deck instead."
	}
	CARD_TEMPLATES["ESD01-012"] = {
		"name": "Godzilla (2023)", "card_type": CardEnums.CardType.BATTLE, "rank": 7,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"counter_power": 7000, "invasion_icon": 2,
		"description": "[Your Turn] When you play a monster card, you may move this card to an unoccupied zone.\nIf this card is in zone 8, this card gains +3000 counter power.\nWhen this card is [Destroy], place this card on the bottom of your deck instead."
	}
	CARD_TEMPLATES["ESD01-013"] = {
		"name": "Ginza Annihilated", "card_type": CardEnums.CardType.STRATEGY, "rank": 4,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"invasion_icon": 1,
		"description": "[Your Turn] Whenever your monster card's [Rage] is increased, [Destroy] 1 of your opponent's rank 6 or lower battle cards."
	}
	CARD_TEMPLATES["ESD01-014"] = {
		"name": "Godzilla Emerges", "card_type": CardEnums.CardType.STRATEGY, "rank": 6,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"invasion_icon": 1,
		"description": "If your monster card has 2 or more [Rage], search your deck for up to 1 battle card named [Godzilla(2023)], play it, then shuffle your deck."
	}
	CARD_TEMPLATES["ESD01-015"] = {
		"name": "Operation Wadatsumi", "card_type": CardEnums.CardType.STRATEGY, "rank": 7,
		"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"invasion_icon": 1,
		"description": "Your opponent discards cards until they have 2 cards remaining in their hand."
	}
	CARD_TEMPLATES["ESD01-016"] = {
		"name": "Heat Ray", "card_type": CardEnums.CardType.STRATEGY, "rank": 1,
		"color": CardEnums.CardColor.WHITE, "trait": CardEnums.CardTrait.GODZILLA,
		"invasion_icon": 1,
		"description": "[Destroy] all of your opponents battle cards in the same column as your monster card."
	}


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

# ESD01 - Godzilla Minus One Starter Deck
var ESD01_MONSTERS: Array[Dictionary] = [
	{
		"id": "ESD01-001", "name": "Godzilla (2023)", "card_type": CardEnums.CardType.MONSTER,
		"rank": 1, "color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"threat_level": 6000, "invasion_icon": 1, "description": ""
	},
	{
		"id": "ESD01-002", "name": "Godzilla (2023)", "card_type": CardEnums.CardType.MONSTER,
		"rank": 2, "color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"threat_level": 8000, "invasion_icon": 1,
		"description": "[When Invading] Search your deck for up to 1 rank _ card named [Godzilla(2023)] with [Burst], reveal it, add it to your hand, then shuffle your deck."
	},
	{
		"id": "ESD01-003", "name": "Godzilla (2023)", "card_type": CardEnums.CardType.MONSTER,
		"rank": 3, "color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"threat_level": 23000, "invasion_icon": 1,
		"description": "If this card has 2 or more [Rage], this card gains +5000 threat level."
	},
	{
		"id": "ESD01-004", "name": "Godzilla (2023)", "card_type": CardEnums.CardType.MONSTER,
		"rank": 4, "color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
		"threat_level": 38000, "invasion_icon": 2,
		"description": "[When Invading] If this card has 2 or more [Rage], your opponent discards cards until they have 2 cards remaining in their hand."
	},
]


# --- Deck Building ---

func get_monster_deck(trait_type: CardEnums.CardTrait) -> Array[Dictionary]:
	match trait_type:
		CardEnums.CardTrait.KAIJU:
			return KAIJU_MONSTERS.duplicate(true)
		CardEnums.CardTrait.MECHA:
			return MECHA_MONSTERS.duplicate(true)
		CardEnums.CardTrait.GODZILLA:
			return ESD01_MONSTERS.duplicate(true)
		_:
			push_error("CardData: No monster deck for trait %s" % trait_type)
			return []


func get_main_deck(deck_id: int) -> Array[Dictionary]:
	return get_esd01_main_deck(deck_id)


func get_esd01_main_deck(deck_id: int) -> Array[Dictionary]:
	## Builds a 50-card main deck from ESD01 (Godzilla Minus One) cards.
	var deck: Array[Dictionary] = []

	# --- Burst Monsters (10 cards, for invasion/rage fuel) ---

	# 4x ESD01-005: Godzilla (2023) Burst I (R2, TL 12000, inv 1)
	for i in range(4):
		deck.append({
			"id": "ESD01-005_%d_%d" % [deck_id, i], "name": "Godzilla (2023)",
			"card_type": CardEnums.CardType.MONSTER, "rank": 2,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"threat_level": 12000, "invasion_icon": 1,
			"description": "[Burst I] You can play this card from rank I. If you do, send this card to your discard pile at the beginning of your next end phase.\n[Enter] Your opponent discards cards until they have 4 cards remaining in their hand."
		})

	# 3x ESD01-006: Godzilla (2023) Burst II (R3, TL 23000, inv 1)
	for i in range(3):
		deck.append({
			"id": "ESD01-006_%d_%d" % [deck_id, i], "name": "Godzilla (2023)",
			"card_type": CardEnums.CardType.MONSTER, "rank": 3,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"threat_level": 23000, "invasion_icon": 1,
			"description": "[Burst II] You can play this card from rank II. If you do, send this card to your discard pile at the beginning of your next end phase.\n[Enter] [Destroy] 1 of your opponents rank 4 or lower battle cards."
		})

	# 3x ESD01-007: Godzilla (2023) Burst III (R4, TL 38000, inv 2)
	for i in range(3):
		deck.append({
			"id": "ESD01-007_%d_%d" % [deck_id, i], "name": "Godzilla (2023)",
			"card_type": CardEnums.CardType.MONSTER, "rank": 4,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"threat_level": 38000, "invasion_icon": 2,
			"description": "[Burst III] You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.\n[Enter] [Destroy] all of your opponents battle cards in the same column as this card."
		})

	# --- Battle Cards (27 cards) ---

	# 8x ESD01-008: Shinseimaru (R2, CP 2000, inv 1)
	for i in range(8):
		deck.append({
			"id": "ESD01-008_%d_%d" % [deck_id, i], "name": "Shinseimaru",
			"card_type": CardEnums.CardType.BATTLE, "rank": 2,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"counter_power": 2000, "invasion_icon": 1,
			"description": "(Battle cards in your hand can be played if their rank is equal to or lower than the number in the zone where the opponent's monster card is.)"
		})

	# 6x ESD01-009: Reinforcements (R4, CP 2000, inv 1)
	for i in range(6):
		deck.append({
			"id": "ESD01-009_%d_%d" % [deck_id, i], "name": "Reinforcements",
			"card_type": CardEnums.CardType.BATTLE, "rank": 4,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"counter_power": 2000, "invasion_icon": 1,
			"description": "[Awakening 4] This card gains +3000 counter power. (Active if your monster card is in zone 4 or beyond.)"
		})

	# 3x ESD01-010: City of Tokyo (R6, CP 0, inv 1)
	for i in range(3):
		deck.append({
			"id": "ESD01-010_%d_%d" % [deck_id, i], "name": "City of Tokyo",
			"card_type": CardEnums.CardType.BATTLE, "rank": 6,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"counter_power": 0, "invasion_icon": 1,
			"description": "If your monster card has 2 or more [Rage], your other battle card in zone 8 gains +5000 counter power.\n[Awakening 6] Your other battle card in zone 8 gains +5000 counter power."
		})

	# 6x ESD01-011: Godzilla (2023) Battle (R5, CP 3000, inv 1)
	for i in range(6):
		deck.append({
			"id": "ESD01-011_%d_%d" % [deck_id, i], "name": "Godzilla (2023)",
			"card_type": CardEnums.CardType.BATTLE, "rank": 5,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"counter_power": 3000, "invasion_icon": 1,
			"description": "[Enter] If your monster card has 2 or more [Rage], reduce your opponent's [Rage] by 1.\nWhen this card is [Destroy], place this card on the bottom of your deck instead."
		})

	# 4x ESD01-012: Godzilla (2023) Battle (R7, CP 7000, inv 2)
	for i in range(4):
		deck.append({
			"id": "ESD01-012_%d_%d" % [deck_id, i], "name": "Godzilla (2023)",
			"card_type": CardEnums.CardType.BATTLE, "rank": 7,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"counter_power": 7000, "invasion_icon": 2,
			"description": "[Your Turn] When you play a monster card, you may move this card to an unoccupied zone.\nIf this card is in zone 8, this card gains +3000 counter power.\nWhen this card is [Destroy], place this card on the bottom of your deck instead."
		})

	# --- Strategy Cards (13 cards) ---

	# 4x ESD01-013: Ginza Annihilated (R4, inv 1)
	for i in range(4):
		deck.append({
			"id": "ESD01-013_%d_%d" % [deck_id, i], "name": "Ginza Annihilated",
			"card_type": CardEnums.CardType.STRATEGY, "rank": 4,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"invasion_icon": 1,
			"description": "[Your Turn] Whenever your monster card's [Rage] is increased, [Destroy] 1 of your opponent's rank 6 or lower battle cards."
		})

	# 3x ESD01-014: Godzilla Emerges (R6, inv 1)
	for i in range(3):
		deck.append({
			"id": "ESD01-014_%d_%d" % [deck_id, i], "name": "Godzilla Emerges",
			"card_type": CardEnums.CardType.STRATEGY, "rank": 6,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"invasion_icon": 1,
			"description": "If your monster card has 2 or more [Rage], search your deck for up to 1 battle card named [Godzilla(2023)], play it, then shuffle your deck."
		})

	# 3x ESD01-015: Operation Wadatsumi (R7, inv 1)
	for i in range(3):
		deck.append({
			"id": "ESD01-015_%d_%d" % [deck_id, i], "name": "Operation Wadatsumi",
			"card_type": CardEnums.CardType.STRATEGY, "rank": 7,
			"color": CardEnums.CardColor.RED, "trait": CardEnums.CardTrait.GODZILLA,
			"invasion_icon": 1,
			"description": "Your opponent discards cards until they have 2 cards remaining in their hand."
		})

	# 3x ESD01-016: Heat Ray (R1, inv 1)
	for i in range(3):
		deck.append({
			"id": "ESD01-016_%d_%d" % [deck_id, i], "name": "Heat Ray",
			"card_type": CardEnums.CardType.STRATEGY, "rank": 1,
			"color": CardEnums.CardColor.WHITE, "trait": CardEnums.CardTrait.GODZILLA,
			"invasion_icon": 1,
			"description": "[Destroy] all of your opponents battle cards in the same column as your monster card."
		})

	# Total: 10 + 27 + 13 = 50 cards
	# Invasion icon 2 count: 3 (ESD01-007) + 4 (ESD01-012) = 7 (under 10 limit)
	return deck


func get_card_by_id(id: String) -> Dictionary:
	for card in KAIJU_MONSTERS + MECHA_MONSTERS + ESD01_MONSTERS:
		if card.get("id") == id:
			return card
	return {}
