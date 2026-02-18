extends Node
## Autoload singleton: card definitions and deck builders

# Card template registry - maps card numbers to their base data (no copy-specific IDs)
var CARD_TEMPLATES: Dictionary = {}


func _ready() -> void:
	_build_card_templates()


func _build_card_templates() -> void:
	# Index all cards by their ID
	for card in EBP01_CARDS:
		CARD_TEMPLATES[card["id"]] = card.duplicate()
	for card in EBP02_CARDS:
		CARD_TEMPLATES[card["id"]] = card.duplicate()
	for card in EBP03_CARDS:
		CARD_TEMPLATES[card["id"]] = card.duplicate()
	for card in EPR_CARDS:
		CARD_TEMPLATES[card["id"]] = card.duplicate()
	for card in ESD01_CARDS:
		CARD_TEMPLATES[card["id"]] = card.duplicate()
	for card in ESD02_CARDS:
		CARD_TEMPLATES[card["id"]] = card.duplicate()


# --- EBP01: Booster Pack 01 ---
var EBP01_CARDS: Array[Dictionary] = [
	{
		"id": "EBP01-001",
		"name": "Godzilla(1954)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 5000,
		"invasion_icon": 1,
		"description": "At the beginning of your counter phase, send the top card of your deck to your discard pile.\nIf it is a monster card, increase this card's <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_001.gd"
	},
	{
		"id": "EBP01-002",
		"name": "Godzilla(1954)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 13000,
		"invasion_icon": 1,
		"description": "<Burst1> (You can play this card from rank I. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<When Invading> Send the top card of your deck to your discard pile. If it is a monster card, <Destroy> 1 of your opponent's rank 5 or lower battle cards.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_002.gd"
	},
	{
		"id": "EBP01-003",
		"name": "Godzilla(1954)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 23000,
		"invasion_icon": 1,
		"description": "Whenever this card's <Rage> is increased, send the top card of your deck to your discard pile. If it is a monster card, <Destroy> 1 of your opponent's rank 6 or lower battle cards.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_003.gd"
	},
	{
		"id": "EBP01-004",
		"name": "Godzilla(1954)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 34000,
		"invasion_icon": 1,
		"description": "<Burst3> (You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.)\nWhen this card reaches zone 8, <Destroy> all battle cards in each player's zones.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_004.gd"
	},
	{
		"id": "EBP01-005",
		"name": "Godzilla(1955)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 37000,
		"invasion_icon": 1,
		"description": "<Burst3> (You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> Your opponent discards cards until they have 4 cards remaining in their hand.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_005.gd"
	},
	{
		"id": "EBP01-006",
		"name": "Godzilla(1974)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 23000,
		"invasion_icon": 2,
		"description": "<Opponent's Turn> At the beginning of the counter phase, <Destroy> all of your opponent's rank 5 or lower battle cards in the same column as this card.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_006.gd"
	},
	{
		"id": "EBP01-007",
		"name": "Godzilla(1975)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 34000,
		"invasion_icon": 1,
		"description": "<Burst3> (You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<When Invading> When this card <Destroy> your battle cards, reduce your opponent's <Rage> by 2.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_007.gd"
	},
	{
		"id": "EBP01-008",
		"name": "Godzilla(2004)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 22000,
		"invasion_icon": 2,
		"description": "<Burst2> (You can play this card from rank II. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> Advance your opponent's monster card by 1 zone.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_008.gd"
	},
	{
		"id": "EBP01-009",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 22000,
		"invasion_icon": 1,
		"description": "<Burst2> (You can play this card from rank II. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<When Invading> If this card has 2 or more <Rage> , <Destroy> 1 of your opponent's rank 6 or lower battle cards.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_009.gd"
	},
	{
		"id": "EBP01-010",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 37000,
		"invasion_icon": 2,
		"description": "Whenever this card's <Rage> is increased, <Destroy> all of your opponent's battle cards in the same column as this card.\n<Opponent's Turn> At the beginning of the counter phase, if this card has 3 or more <Rage> , <Destroy> all of your opponent's battle cards in the same column as this card.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_010.gd"
	},
	{
		"id": "EBP01-011",
		"name": "Godzilla(Fest Godzilla)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FEST],
		"threat_level": 4000,
		"invasion_icon": 1,
		"description": "When this card advances into the same column as your opponent's monster card, advance your opponent's monster card by 1 zone.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_011.gd"
	},
	{
		"id": "EBP01-012",
		"name": "Godzilla(Fest Godzilla)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FEST],
		"threat_level": 13000,
		"invasion_icon": 1,
		"description": "At the beginning of your end phase, if this card invaded this turn, advance your opponent's monster card by 1 zone.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_012.gd"
	},
	{
		"id": "EBP01-013",
		"name": "Godzilla(Fest Godzilla)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FEST],
		"threat_level": 19000,
		"invasion_icon": 1,
		"description": "<Burst2> (You can play this card from rank II. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> If you have 4 or more battle cards in your zones, reduce your opponent's <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_013.gd"
	},
	{
		"id": "EBP01-014",
		"name": "Godzilla(Fest Godzilla)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FEST],
		"threat_level": 34000,
		"invasion_icon": 1,
		"description": "<Opponent's Turn> <Awakening4> If you have 2 or more battle cards in your zones, all of your opponent's rank 5 or lower battle cards cannot engage with this card. (Their counter power is not included in the total counter power during the counter phase.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_014.gd"
	},
	{
		"id": "EBP01-015",
		"name": "Godzilla(Fest Godzilla)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FEST],
		"threat_level": 28000,
		"invasion_icon": 1,
		"description": "<Your Turn> <Enter> Reveal the top 5 cards of your deck and send them to your discard pile. For each monster card revealed this way, increase this card's <Rage> by 1. If a card with <Step2> is revealed this way, this card advances to zone 6.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_015.gd"
	},
	{
		"id": "EBP01-016",
		"name": "Ebirah(2004)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.EBIRAH, CardEnums.CardTrait.FINAL_WARS],
		"counter_power": 1000,
		"invasion_icon": 1
	},
	{
		"id": "EBP01-017",
		"name": "Kumonga(2004)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.KUMONGA, CardEnums.CardTrait.FINAL_WARS],
		"counter_power": 1000,
		"invasion_icon": 1,
		"description": "If this card is in zone 8, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_017.gd"
	},
	{
		"id": "EBP01-018",
		"name": "Mechagodzilla(1974)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 1000,
		"invasion_icon": 1,
		"description": "<Awakening4> This card gains +3000 counter power. (Active if your monster card is in zone 4 or beyond.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_018.gd"
	},
	{
		"id": "EBP01-019",
		"name": "Kamacuras(1967)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.KAMACURAS],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "<Awakening6> <Enter> If this card was played from your hand, search your deck for up to 2 <《Kamacuras》> battle cards, play them, then shuffle your deck. (Active if your monster card is in zone 6 or beyond.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_019.gd"
	},
	{
		"id": "EBP01-020",
		"name": "Anguirus(1968)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.ANGUIRUS],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "If this card is in zone 8, whenever your monster card invades, you may reduce its <Rage> by 1 to search your deck for up to 1 monster card with <Burst> , reveal it, add it to your hand, then shuffle your deck.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_020.gd"
	},
	{
		"id": "EBP01-021",
		"name": "Rodan(1968)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.RODAN],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Enter> If this card is in the same column as your opponent's monster card, look at the top 2 cards of your deck, put any number on top of your deck in any order, and send the rest to your discard pile.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_021.gd"
	},
	{
		"id": "EBP01-022",
		"name": "Titanosaurus",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.TITANOSAURUS],
		"counter_power": 4000,
		"invasion_icon": 1,
		"description": "<Your Turn> Whenever your monster card's <Rage> is increased, you may move 1 of your other battle cards in your zones to an unoccupied zone.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_022.gd"
	},
	{
		"id": "EBP01-023",
		"name": "Mechagodzilla(1975)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 4000,
		"invasion_icon": 1,
		"description": "If your monster card has 2 or more <Rage> , this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_023.gd"
	},
	{
		"id": "EBP01-024",
		"name": "Minilla(2004)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MINILLA, CardEnums.CardTrait.FINAL_WARS],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "<Enter> Reduce your opponent's <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_024.gd"
	},
	{
		"id": "EBP01-025",
		"name": "King Caesar(1974)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.KING_CAESAR],
		"counter_power": 4000,
		"invasion_icon": 1,
		"description": "If this card is in a zone adjacent to your monster card, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_025.gd"
	},
	{
		"id": "EBP01-026",
		"name": "Jet Jaguar(2023)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.JET_JAGUAR, CardEnums.CardTrait.MECH, CardEnums.CardTrait.FEST],
		"counter_power": 7000,
		"invasion_icon": 2,
		"description": "At the beginning of your counter phase, you may place 1 card with both <《Gigan》> and <《Fest》> from your discard pile under this card.\nIf there is a card under this card, this card gains +5000 counter power.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_026.gd"
	},
	{
		"id": "EBP01-027",
		"name": "Hedorah(1971)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.HEDORAH],
		"counter_power": 7000,
		"invasion_icon": 2,
		"description": "When playing this card from your hand, you can reduce its rank by 1 for each battle card in your zones. (After being played this card is rank 8)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_027.gd"
	},
	{
		"id": "EBP01-028",
		"name": "Godzilla vs. Mechagodzilla",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"description": "<Opponent's Turn> All of your opponent's rank 3 or lower battle cards cannot engage with your monster card. (Their counter power is not included in the total during the counter phase.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_028.gd"
	},
	{
		"id": "EBP01-029",
		"name": "Unthinkable Destruction",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"description": "Choose 1 of your opponent's zones. <Destroy> all of your opponent's rank 5 or lower battle cards in that zone and zones adjacent to it.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_029.gd"
	},
	{
		"id": "EBP01-030",
		"name": "Godzilla Landing",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"description": "Advance the opponent's monster card by 1 zone.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_030.gd"
	},
	{
		"id": "EBP01-031",
		"name": "Space Beam",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 5,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 2,
		"description": "If your monster card has 2 or more <Rage> , your opponent discards cards until they have 2 cards remaining in their hand.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_031.gd"
	},
	{
		"id": "EBP01-032",
		"name": "Heat Ray Charge",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 2,
		"description": "Draw 2 cards.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_032.gd"
	},
	{
		"id": "EBP01-033",
		"name": "Final Showdown",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 8,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"description": "You can play this card from your hand with its rank reduced by 1 for each zone your monster card invaded this turn.\n<Destroy> all battle cards of both players.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_033.gd"
	},
	{
		"id": "EBP01-034",
		"name": "Godzilla(1989)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 13000,
		"invasion_icon": 1,
		"description": "<Enter> Select 1 rank 4 or lower battle card with <Evolution> from your discard pile and play it in a zone adjacent to this card.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_034.gd"
	},
	{
		"id": "EBP01-035",
		"name": "Godzilla(1989)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 23000,
		"invasion_icon": 1,
		"description": "<Enter> Evolve all of your rank 4 or lower battle cards with <Evolution> in zones adjacent to this card.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_035.gd"
	},
	{
		"id": "EBP01-036",
		"name": "Godzilla(1992)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 36000,
		"invasion_icon": 1,
		"description": "<Enter> Evolve all of your battle cards with <Evolution> in zones adjacent to this card.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_036.gd"
	},
	{
		"id": "EBP01-037",
		"name": "Godzilla(1995)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 22000,
		"invasion_icon": 1,
		"description": "Whenever this card advances, you may discard 1 strategy card from your hand to increase its <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_037.gd"
	},
	{
		"id": "EBP01-038",
		"name": "Godzilla(1995)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 34000,
		"invasion_icon": 1,
		"description": "<Opponent's Turn> <Awakening6> This card cannot be countered by 50,000 or lower counter power, instead, it only moves as though it were countered. (Do not play the next monster card from your monster deck.) (Active if this card is in zone 6 or beyond, and the opponent's total counter power is 50,000 or lower.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_038.gd"
	},
	{
		"id": "EBP01-039",
		"name": "Godzilla(1999)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 15000,
		"invasion_icon": 2,
		"description": "<When Invading> Discard 1 monster card from your hand： <Destroy> all of your opponent's rank 5 or lower battle cards in zones 1-5.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_039.gd"
	},
	{
		"id": "EBP01-040",
		"name": "Godzilla(1999)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 33000,
		"invasion_icon": 2,
		"description": "<Enter> <Destroy> 1 of your opponent's rank 7 or lower battle cards.\n<When Invading> If you have 5 or more monster cards in your discard pile, increase this card's <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_040.gd"
	},
	{
		"id": "EBP01-041",
		"name": "Godzilla(2000)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 5000,
		"invasion_icon": 1,
		"description": "<When Invading> <Destroy> 1 of your opponent's rank 4 or lower battle cards.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_041.gd"
	},
	{
		"id": "EBP01-042",
		"name": "Godzilla(2000)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 18000,
		"invasion_icon": 1,
		"description": "<Enter> If you have 5 or more monster cards in your discard pile, you may discard 1 card from your hand to reduce your opponent's <Rage> by 1.\nIf you have 5 or more monster cards in your discard pile, this card gains +10,000 threat level.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_042.gd"
	},
	{
		"id": "EBP01-043",
		"name": "Godzilla(2000)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 36000,
		"invasion_icon": 1,
		"description": "<Awakening4> When you successfully counter your opponent's monster card, if you have 5 or more monster cards in your discard pile, <Destroy> all of your opponent's rank 6 or lower battle cards. (Active if this card is in zone 4 or beyond.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_043.gd"
	},
	{
		"id": "EBP01-044",
		"name": "Mothra(egg)(1992)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 0,
		"invasion_icon": 1,
		"description": "<Evolution5> <《Mothra》> (At the beginning of your main phase, you may play a rank 5 or lower <《Mothra》> battle card from your deck by placing it on top of this card.)",
		"evolution_rank": 5,
		"evolution_trait": CardEnums.CardTrait.MOTHRA,
		"effect_script": "res://scripts/effects/ebp01/ebp01_044.gd"
	},
	{
		"id": "EBP01-045",
		"name": "Meganula",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MEGANULA],
		"counter_power": 1000,
		"invasion_icon": 1,
		"description": "<Enter> If this card is in the same column as your opponent's monster card and you have 2 or more battle cards in your zones, reduce your opponent's <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_045.gd"
	},
	{
		"id": "EBP01-046",
		"name": "MBT-MB92",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.WEAPON],
		"counter_power": 1000,
		"invasion_icon": 1,
		"unlimited_copies": true,
		"description": "You may have any number of this card in your deck.\n<Awakening6> This card gains +3000 counter power. (Active if your monster card is in zone 6 or beyond.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_046.gd"
	},
	{
		"id": "EBP01-047",
		"name": "Orga",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.ORGA],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "<Enter> Draw 1 card, then discard 1 card.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_047.gd"
	},
	{
		"id": "EBP01-048",
		"name": "Biollante Rose Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BIOLLANTE],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "<Evolution7> <《Biollante》> (At the beginning of your main phase, you may play a rank 7 or lower battle card with <《Biollante》> from your deck by placing it on top of this card.)",
		"evolution_rank": 7,
		"evolution_trait": CardEnums.CardTrait.BIOLLANTE,
		"effect_script": "res://scripts/effects/ebp01/ebp01_048.gd"
	},
	{
		"id": "EBP01-049",
		"name": "Destoroyah Aggregate Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.DESTOROYAH],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Evolution6> <《Destoroyah》> (At the beginning of your main phase, you may play a rank 6 or lower <《Destoroyah》> battle card from your deck by placing it on top of this card.)",
		"evolution_rank": 6,
		"evolution_trait": CardEnums.CardTrait.DESTOROYAH,
		"effect_script": "res://scripts/effects/ebp01/ebp01_049.gd"
	},
	{
		"id": "EBP01-050",
		"name": "Mothra(larva)(1992)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Evolution7> <《Mothra》> (At the beginning of your main phase, you may play a rank 7 or lower <《Mothra》> battle card from your deck by placing it on top of this card.)",
		"evolution_rank": 7,
		"evolution_trait": CardEnums.CardTrait.MOTHRA,
		"effect_script": "res://scripts/effects/ebp01/ebp01_050.gd"
	},
	{
		"id": "EBP01-051",
		"name": "Orga Phase II",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.ORGA],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "If you have 5 or more monster cards in your discard pile, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_051.gd"
	},
	{
		"id": "EBP01-052",
		"name": "Megaguirus",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MEGAGUIRUS],
		"counter_power": 3000,
		"invasion_icon": 2,
		"description": "<Awakening4> If this card is in zones 1-5 and you have 5 or more monster cards in your discard pile, this card cannot be <Destroy> by your opponent's effects. (Active if your monster card is in zone 4 or beyond.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_052.gd"
	},
	{
		"id": "EBP01-053",
		"name": "Rodan(1993)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.RODAN],
		"counter_power": 5000,
		"invasion_icon": 1
	},
	{
		"id": "EBP01-054",
		"name": "Destoroyah Flying Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.DESTOROYAH],
		"counter_power": 4000,
		"invasion_icon": 1,
		"description": "<Evolution8> <《Destoroyah》> (At the beginning of your main phase, you may play a rank 8 or lower <《Destoroyah》> battle card from your deck by placing it on top of this card.)\n<Enter> If this card was played through evolution, draw 2 cards, then discard 2 cards.",
		"evolution_rank": 8,
		"evolution_trait": CardEnums.CardTrait.DESTOROYAH,
		"effect_script": "res://scripts/effects/ebp01/ebp01_054.gd"
	},
	{
		"id": "EBP01-055",
		"name": "Battra(imago)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BATTRA],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "<Enter> Draw 1 card, then discard 1 card.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_055.gd"
	},
	{
		"id": "EBP01-056",
		"name": "Super X2",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.SUPER_X, CardEnums.CardTrait.WEAPON],
		"counter_power": 5000,
		"invasion_icon": 2,
		"description": "If this card is in the same column as your opponent's monster card, this card gains +3000 counter power for each of your opponent's <Rage> .",
		"effect_script": "res://scripts/effects/ebp01/ebp01_056.gd"
	},
	{
		"id": "EBP01-057",
		"name": "Mothra(imago)(1992)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 5000,
		"invasion_icon": 2,
		"description": "<Enter> Choose 2 battle cards in your zones, you may swap their positions.\nYour rank 5 or lower battle cards in zones adjacent to this card gain +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_057.gd"
	},
	{
		"id": "EBP01-058",
		"name": "Biollante Plant Beast Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BIOLLANTE],
		"counter_power": 6000,
		"invasion_icon": 1,
		"description": "If you have a <《Biollante》> card with <Evolution> in your discard pile, you can play this from your hand with its rank reduced by 2. (After being played, this card is rank 7.)\n<Enter> Return all cards in your discard pile to your deck then shuffle.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_058.gd"
	},
	{
		"id": "EBP01-059",
		"name": "Fire Rodan",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.RODAN],
		"counter_power": 6000,
		"invasion_icon": 1,
		"description": "When this card is discarded from your hand by your opponent's effect, and their monster card is in zones 4-8, you may play this card. (Regardless of what zone your opponent's monster card is occupying.)\nIf this card is in zone 8, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_059.gd"
	},
	{
		"id": "EBP01-060",
		"name": "Destoroyah Perfect Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.DESTOROYAH],
		"counter_power": 10000,
		"invasion_icon": 1,
		"description": "<Enter> If this card was played through evolution, choose up to 1 strategy card named 「Godzilla vs. Destoroyah」in your discard pile.\nIf you have 1 or fewer strategy cards in play, play and activate the chosen card. (Regardless of rank.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_060.gd"
	},
	{
		"id": "EBP01-061",
		"name": "Scale Attack",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 1,
		"description": "If your opponent has 5 or more <Rage> , reduce their <Rage> by 3.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_061.gd"
	},
	{
		"id": "EBP01-062",
		"name": "Godzilla vs. Destoroyah",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 2,
		"description": "<Your Turn> If you have a <《Destoroyah》> battle card in your zones, increase your total counter power by +10,000.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_062.gd"
	},
	{
		"id": "EBP01-063",
		"name": "Guardians Awaken",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 2,
		"description": "Evolve all of your rank 4 or lower battle cards with <Evolution> .",
		"effect_script": "res://scripts/effects/ebp01/ebp01_063.gd"
	},
	{
		"id": "EBP01-064",
		"name": "Godzilla vs. Megaguirus",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 1,
		"description": "Choose one of the following:\n・ <Destroy> 1 of your opponent's rank 4 or lower battle cards.\n・If you have 4 or more battle cards in your zones, choose 1 of your opponent's zones and <Destroy> all battle cards in that zone and zones adjacent to it.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_064.gd"
	},
	{
		"id": "EBP01-065",
		"name": "Godzilla vs. Destoroyah",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 1,
		"description": "<Destroy> all of your opponent's battle cards in zones 1-5.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_065.gd"
	},
	{
		"id": "EBP01-066",
		"name": "Godzilla vs. Biollante",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 1,
		"description": "When this card is discarded from your hand by your opponent's effect, increase your monster card's <Rage> by 2.\n<Opponent's Turn> Your monster card cannot be countered by 40,000 or lower counter power. Instead, it only moves as though it were countered. (Do not play the next monster card from your monster deck.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_066.gd"
	},
	{
		"id": "EBP01-067",
		"name": "Gorosaurus",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.GOROSAURUS],
		"counter_power": 1000,
		"invasion_icon": 2,
		"description": "<Awakening4> This card gains +3000 counter power. (Active if your monster card is in zone 4 or beyond.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_067.gd"
	},
	{
		"id": "EBP01-068",
		"name": "Manda(1968)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.MANDA],
		"counter_power": 1000,
		"invasion_icon": 1,
		"description": "If this card is in a zone adjacent to your monster card, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_068.gd"
	},
	{
		"id": "EBP01-069",
		"name": "Varan",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.VARAN],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Awakening6> <Enter> Draw 2 cards, then discard 2 cards. (Active if your monster card is in zone 6 or beyond.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_069.gd"
	},
	{
		"id": "EBP01-070",
		"name": "Baragon(1968)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.BARAGON],
		"counter_power": 4000,
		"invasion_icon": 1,
		"description": "<Enter> Look at the top card of your deck. You may send it to your discard pile or place it back on top of your deck.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_070.gd"
	},
	{
		"id": "EBP01-071",
		"name": "Giant Condor",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.GIANT_CONDOR],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "If this card is in the same column as your opponent's monster card, this card gains +5000 counter power.\nWhen your opponent's <Rage> is increased, <Destroy> this card.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_071.gd"
	},
	{
		"id": "EBP01-072",
		"name": "Gigan(2022)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.WEAPON, CardEnums.CardTrait.FEST],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "<Enter> If this card is in the same column as your opponent's monster card, send the top card of your deck to your discard pile. If it is a battle card, move your opponent's monster card with 50,000 or lower threat level backward by 1 zone.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_072.gd"
	},
	{
		"id": "EBP01-073",
		"name": "Godzilla Against Mechagodzilla",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 10000,
		"invasion_icon": 2,
		"description": "This card cannot be played if you have 7 or fewer monster cards in your discard pile.\nWhen your monster card invades, if there are no monster cards under this card, you may place 1 monster card from your discard pile under this card to set your opponent's <Rage> to 0.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_073.gd"
	},
	{
		"id": "EBP01-074",
		"name": "King Ghidorah(2024)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH, CardEnums.CardTrait.FEST],
		"counter_power": 8000,
		"invasion_icon": 1,
		"description": "If you have a card named 「Gravity Beam」 in play, this card gains +20,000 counter power.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_074.gd"
	},
	{
		"id": "EBP01-075",
		"name": "Godzilla, King of the Monsters",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 5000,
		"invasion_icon": 2,
		"description": "This card gains +3000 counter power for each of your monster card's <Rage> .\nIf your monster card has 3 or more <Rage> , and this card is in zones 1-5, this card cannot be <Destroy> by your opponent's effects.\n<Awakening8> You can play this card with its rank reduced by 4. (Active if your monster card is in zone 8. After being played, this card is rank 8.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_075.gd"
	},
	{
		"id": "EBP01-076",
		"name": "Destroy All Monsters",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 2,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 1,
		"description": "When your monster card invades this turn, <Destroy> 1 of your opponent's battle cards.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_076.gd"
	},
	{
		"id": "EBP01-077",
		"name": "Oxygen Destroyer",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 1,
		"description": "If your opponent has 2 or fewer <Rage> , move your opponent's monster card as though it were countered. (Do not play the next monster card from your monster deck.)",
		"effect_script": "res://scripts/effects/ebp01/ebp01_077.gd"
	},
	{
		"id": "EBP01-078",
		"name": "Godzilla Attacks",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 2,
		"description": "Advance your monster card to zone 6.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_078.gd"
	},
	{
		"id": "EBP01-079",
		"name": "Gravity Beam",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 5,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 2,
		"description": "Your opponent discards cards until they have 3 cards remaining in their hand.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_079.gd"
	},
	{
		"id": "EBP01-080",
		"name": "Godzilla and its son on Monster Island",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 1,
		"description": "If your opponent has a strategy card in play, you can play this from your hand with its rank reduced by 2.\nWhile this card is in the strategy zone, your rank 5 or lower battle cards in zones 1-5 cannot be <Destroy> by your opponent's effects.",
		"effect_script": "res://scripts/effects/ebp01/ebp01_080.gd"
	},
]

# --- EBP02: Booster Pack 02 ---
var EBP02_CARDS: Array[Dictionary] = [
	{
		"id": "EBP02-001",
		"name": "Giant Unknown Creature",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 4000,
		"invasion_icon": 1,
		"description": "<Opponent's Turn> At the beginning of the counter phase, you may discard 1 strategy card from your hand to increase this card's <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_001.gd"
	},
	{
		"id": "EBP02-002",
		"name": "Godzilla(2016) 2nd Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.SECOND_FORM],
		"threat_level": 11000,
		"invasion_icon": 1,
		"description": "If you have 1 or more strategy cards in play, this card gains +5000 threat level.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_002.gd"
	},
	{
		"id": "EBP02-003",
		"name": "Godzilla(2016) 2nd Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.SECOND_FORM],
		"threat_level": 12000,
		"invasion_icon": 1,
		"description": "<Burst3> (You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> If there is a card named “Giant Unknown Creature” under this card, you may discard 1 strategy card from your hand to advance this card by 1 zone.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_003.gd"
	},
	{
		"id": "EBP02-004",
		"name": "Godzilla(2016) 3rd Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.THIRD_FORM],
		"threat_level": 22000,
		"invasion_icon": 1,
		"description": "<Burst2> (You can play this card from rank II. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> If there is a <《2nd Form》> card under this card, <Destroy> 1 of your opponent's rank 6 or lower battle cards for each strategy card in your strategy zone.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_004.gd"
	},
	{
		"id": "EBP02-005",
		"name": "Godzilla(2016) 3rd Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.THIRD_FORM],
		"threat_level": 23000,
		"invasion_icon": 1,
		"description": "<Your Turn> <Awakening6> Whenever this card's <Rage> is increased, if you have a strategy card in play, your opponent discards cards until they have 3 cards remaining in their hand.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_005.gd"
	},
	{
		"id": "EBP02-006",
		"name": "Godzilla(2016) 4th Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FOURTH_FORM],
		"threat_level": 33000,
		"invasion_icon": 2,
		"description": "<When Invading> If there is a card with <《3rd Form》> under this card, <Destroy> all of your opponent's rank 6 or lower battle cards.\nIf there is a <《4th Form》> card under this card, this card gains +10,000 threat level for each strategy card in your strategy zone.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_006.gd"
	},
	{
		"id": "EBP02-007",
		"name": "Godzilla(2016) 4th Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FOURTH_FORM],
		"threat_level": 36000,
		"invasion_icon": 1,
		"description": "<Burst3> (You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> You may discard 1 strategy card from your hand. If you do, reveal the top 5 cards of your deck, add 1 monster card from among them to your hand, then send the rest to your discard pile.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_007.gd"
	},
	{
		"id": "EBP02-008",
		"name": "Godzilla(1969)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 24000,
		"invasion_icon": 2,
		"description": "<Burst4> (You can play this card from rank Ⅳ. If you do, send this card to your discard pile at the beginning of your next end phase.)\nWhenever this card's <Rage> is increased, <Destroy> all of your opponent's rank 6 or lower battle cards in the zone with the same number as the zone this card occupies.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_008.gd"
	},
	{
		"id": "EBP02-009",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 35000,
		"invasion_icon": 1,
		"description": "<Burst3> (You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.)\nWhen this card is discarded by the effect of Burst, return this card from your discard pile to your hand.\n<When Invading> Your opponent discards cards until they have 3 cards remaining in their hand.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_009.gd"
	},
	{
		"id": "EBP02-010",
		"name": "King Caesar(2004)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.FINAL_WARS],
		"counter_power": 1000,
		"invasion_icon": 1,
		"description": "<Enter> Move 1 of your other battle cards in your zones to an unoccupied zone.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_010.gd"
	},
	{
		"id": "EBP02-011",
		"name": "Gabara",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GABARA],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "If your monster card has 2 or more <Rage> , this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_011.gd"
	},
	{
		"id": "EBP02-012",
		"name": "Godzilla(2016) Frozen",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FOURTH_FORM],
		"counter_power": 0,
		"invasion_icon": 1,
		"description": "If this card is in zone 8, whenever your strategy cards would be discarded from the strategy zone, you may place them under this card instead.\n<Awakening4> At the beginning of your main phase, if there are 2 or more cards under this card, counter your opponent's monster card.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_012.gd"
	},
	{
		"id": "EBP02-013",
		"name": "Minilla(1969)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MINILLA],
		"counter_power": 2000,
		"invasion_icon": 2,
		"description": "<Enter> If your monster card has 2 or more <Rage> , advance your monster card to zone 5.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_013.gd"
	},
	{
		"id": "EBP02-014",
		"name": "Cabinet Helicopter",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MECH],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Enter> Send the top card of your deck to your discard pile. If it is a monster card, advance your monster card to zone 6.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_014.gd"
	},
	{
		"id": "EBP02-015",
		"name": "Rodan(2004)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.RODAN, CardEnums.CardTrait.WEAPON],
		"counter_power": 4000,
		"invasion_icon": 1,
		"description": "If this card is in a zone with the same number as the zone that your opponent's monster card occupies, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_015.gd"
	},
	{
		"id": "EBP02-016",
		"name": "Anguirus(2004)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.ANGUIRUS, CardEnums.CardTrait.FINAL_WARS],
		"counter_power": 7000,
		"invasion_icon": 1,
		"description": "If this card is in the same column as the opponent's monster card, this card gains +5000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_016.gd"
	},
	{
		"id": "EBP02-017",
		"name": "Operation Taba",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"description": "<Your Turn> If you have 4 or more battle cards in your zones, increase your total counter power by 5000.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_017.gd"
	},
	{
		"id": "EBP02-018",
		"name": "Despair",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"description": "If your monster card has 2 or more <Rage> , <Destroy> 1 of your opponent's battle cards that is occupying a zone at or before the zone your monster card currently occupies. (If your monster card is in Zone 4, you can select battle cards in your opponent's zone 1, 2, 3, or 4.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_018.gd"
	},
	{
		"id": "EBP02-019",
		"name": "There is no danger of the creature coming ashore.",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"description": "Move 1 battle card in your zones to an unoccupied zone. If your monster card invaded this turn, advance your monster card by 1 zone.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_019.gd"
	},
	{
		"id": "EBP02-020",
		"name": "Operation Yashiori -Conductorless train bombers-",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp02/ebp02_020.gd",
		"description": "If you have 5 or more strategy cards in your discard pile, create “Conductorless train bombers” tokens in each of your unoccupied zones. (Tokens are prepared separately from your main deck.)"
	},
	{
		"id": "EBP02-021",
		"name": "Godzilla(1993)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 25000,
		"invasion_icon": 2,
		"description": "All of your rank 5 or lower battle cards in zones adjacent to this card gain +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_021.gd"
	},
	{
		"id": "EBP02-022",
		"name": "Godzilla(1994)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 36000,
		"invasion_icon": 1,
		"description": "<When Invading> If you discarded a blue battle card for this card's invade action, you may play that battle card from your discard pile.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_022.gd"
	},
	{
		"id": "EBP02-023",
		"name": "Godzilla(1999)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 34000,
		"invasion_icon": 1,
		"description": "<Enter> If you have 5 or more monster cards in your discard pile, 1 of your opponent's monster cards with 50,000 or less threat level retreats back by 1 zone.\nIf you have 10 or more monster cards in your discard pile, this card gains +10,000 threat level.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_023.gd"
	},
	{
		"id": "EBP02-024",
		"name": "Biollante Rose Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BIOLLANTE],
		"threat_level": 6000,
		"invasion_icon": 1,
		"start_zone": 5,
		"effect_script": "res://scripts/effects/ebp02/ebp02_024.gd",
		"description": "If this card is in your monster deck, at the start of the game it will be played in Zone 5.\nThis card cannot advance nor invade."
	},
	{
		"id": "EBP02-025",
		"name": "Biollante Rose Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BIOLLANTE],
		"threat_level": 11000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_025.gd",
		"description": "This card cannot advance nor invade.\n<Enter> Play 1 “Tentacles” token in a zone adjacent to this card. (Tokens are prepared separately from your main deck.)"
	},
	{
		"id": "EBP02-026",
		"name": "Biollante Plant Beast Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BIOLLANTE],
		"threat_level": 22000,
		"invasion_icon": 1,
		"description": "<Enter> If you have a strategy card in play, choose 1 of your opponent's zones. <Destroy> all of your opponent's rank 5 or lower battle cards in that zone and zones adjacent to it.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_026.gd"
	},
	{
		"id": "EBP02-027",
		"name": "Biollante Plant Beast Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BIOLLANTE],
		"threat_level": 23000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_027.gd",
		"description": "<Opponent's Turn> <Awakening6> If your opponent has a strategy card in play, this card cannot be countered by 40,000 or lower counter power. Instead, it only moves as though it were countered. (Do not play the next Monster Card from your monster deck.)"
	},
	{
		"id": "EBP02-028",
		"name": "Biollante Plant Beast Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BIOLLANTE],
		"threat_level": 32000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp02/ebp02_028.gd",
		"description": "<Enter> Play as many rank 4 or lower battle cards with <Evolution> from your discard pile to each of this card's adjacent zones. (You must play as many as possible and you may play the battle cards in zones already occupied by other battle cards. Maximum of 3 cards.)"
	},
	{
		"id": "EBP02-029",
		"name": "Biollante Plant Beast Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BIOLLANTE],
		"threat_level": 55000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_029.gd",
		"description": "<Opponent's Turn> At the beginning of the counter phase, for the rest of the turn, double the counter power of all of your opponent's battle cards in the same column as this card. (Refer to those battle card's counter power at the ability resolution timing.)"
	},
	{
		"id": "EBP02-030",
		"name": "Baby Godzilla",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BABY_GODZILLA],
		"counter_power": 0,
		"invasion_icon": 1,
		"description": "<Evolution5> <《Little Godzilla》> (At the beginning of your main phase, you may play a rank 5 or lower <《Little Godzilla》> battle card from your deck by placing it on top of this card.)",
		"evolution_rank": 5,
		"evolution_trait": CardEnums.CardTrait.LITTLE_GODZILLA,
		"effect_script": "res://scripts/effects/ebp02/ebp02_030.gd"
	},
	{
		"id": "EBP02-031",
		"name": "MBT-MB92 modified",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.WEAPON],
		"counter_power": 2000,
		"invasion_icon": 1,
		"unlimited_copies": true,
		"description": "You may have any number of this card in your deck.\nIf the number of other rank 5 or lower battle cards in your zones is 2 or more, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_031.gd"
	},
	{
		"id": "EBP02-032",
		"name": "Biollante Rose Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BIOLLANTE],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Evolution7> <《Biollante》> (At the beginning of your main phase, you may play a rank 7 or lower <《Biollante》> battle card from your deck by placing it on top of this card.)",
		"evolution_rank": 7,
		"evolution_trait": CardEnums.CardTrait.BIOLLANTE,
		"effect_script": "res://scripts/effects/ebp02/ebp02_032.gd"
	},
	{
		"id": "EBP02-033",
		"name": "Little Godzilla",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.LITTLE_GODZILLA],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Awakening4> This card gains +3000 counter power. (Active if your monster card is in zone 4 or beyond.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_033.gd"
	},
	{
		"id": "EBP02-034",
		"name": "Super X3",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.SUPER_X, CardEnums.CardTrait.WEAPON],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "If this card is in zone 8, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_034.gd"
	},
	{
		"id": "EBP02-035",
		"name": "Biollante Plant Beast Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BIOLLANTE],
		"counter_power": 5000,
		"invasion_icon": 2,
		"description": "<Enter> If you have 2 or more cards with ⁅《ビオランテ＠》⁆ in your discard pile, return all cards in your opponent's discard pile to their deck then shuffle.\n<Enter> Play 2 “Tentacles” tokens in zones adjacent to this card. (Tokens are prepared separately from your main deck.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_035.gd"
	},
	{
		"id": "EBP02-036",
		"name": "Godzilla(1994)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 6000,
		"invasion_icon": 1,
		"description": "At the beginning of your end phase, if this card is in a zone adjacent to your monster card, 1 of your opponent's monster cards with 40,000 or less threat level retreats back by 1 zone.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_036.gd"
	},
	{
		"id": "EBP02-037",
		"name": "Destoroyah Perfect Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.DESTOROYAH],
		"counter_power": 9000,
		"invasion_icon": 1,
		"description": "<Enter> Draw 2 cards, then discard 2 cards.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_037.gd"
	},
	{
		"id": "EBP02-038",
		"name": "Godzilla 2000: Millennium",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 1,
		"description": "Choose one of the following:\n\n・ <Destroy> 1 of your opponent's rank 5 or lower battle cards.\n・If you have 10 or more monster cards in your discard pile, <Destroy> 1 of your opponent's battle cards in zone 8.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_038.gd"
	},
	{
		"id": "EBP02-039",
		"name": "Lake Ashi Monster",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 1,
		"description": "<Your Turn> You can play battle cards with <《Biollante》> from your hand with their rank reduced by 3. (They return to their original rank after being played.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_039.gd"
	},
	{
		"id": "EBP02-040",
		"name": "Interception Operation",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 2,
		"description": "If you have 5 or more <《Weapon》> battle cards with “MB” in their name in your zones, discard your hand and draw 5 cards.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_040.gd"
	},
	{
		"id": "EBP02-041",
		"name": "Gigan(1972)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.WEAPON],
		"threat_level": 5000,
		"invasion_icon": 1,
		"description": "Each of your battle cards in zones adjacent to this card gain +1000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_041.gd"
	},
	{
		"id": "EBP02-042",
		"name": "Gigan(1972)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.WEAPON],
		"threat_level": 11000,
		"invasion_icon": 1,
		"description": "<Enter> You may discard a card with <《King Ghidorah》> or <《Megalon》> from your hand to reduce your opponent's <Rage> by 2.\nAt the beginning of your end phase, if your opponent's monster card is in zone 1–5, increase this card's <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_042.gd"
	},
	{
		"id": "EBP02-043",
		"name": "Gigan(2004)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.WEAPON],
		"threat_level": 18000,
		"invasion_icon": 1,
		"description": "Each of your battle cards in zones adjacent to this card gain +1000 counter power for each card under this card.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_043.gd"
	},
	{
		"id": "EBP02-044",
		"name": "Modified Gigan",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.WEAPON],
		"threat_level": 32000,
		"invasion_icon": 2,
		"description": "<When Invading> If your opponent's monster card is in zones 6–8, reduce their <Rage> by 2.\nAt the beginning of your end phase, if your opponent's monster card is in zones 1–5, increase this card's <Rage> by 2.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_044.gd"
	},
	{
		"id": "EBP02-045",
		"name": "King Ghidorah(1964)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"threat_level": 11000,
		"invasion_icon": 1,
		"description": "This card gains +3000 threat level for each rank of your opponent's monster.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_045.gd"
	},
	{
		"id": "EBP02-046",
		"name": "King Ghidorah(1965)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"threat_level": 23000,
		"invasion_icon": 1,
		"description": "<Enter> Place all cards with the same name as this card from your discard pile under this card.\nThis card gains +3000 threat level for each card with the same name under this card.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_046.gd"
	},
	{
		"id": "EBP02-047",
		"name": "King Ghidorah(1991)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"threat_level": 5000,
		"invasion_icon": 1,
		"description": "Whenever this card advances, send the top card of your deck to your discard pile.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_047.gd"
	},
	{
		"id": "EBP02-048",
		"name": "King Ghidorah(1991)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"threat_level": 11000,
		"invasion_icon": 1,
		"description": "<Enter> Send the top 3 cards of your deck to your discard pile.\n<When Invading> <Destroy> 3 of your opponent's rank 4 or lower battle cards.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_048.gd"
	},
	{
		"id": "EBP02-049",
		"name": "King Ghidorah(1991)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"threat_level": 21000,
		"invasion_icon": 1,
		"description": "<Enter> If there are 3 or more cards under this card, choose one of the following:\n・ <Destroy> 3 of your opponent's rank 5 or lower battle cards.\n・Your opponent discards cards until they have 3 cards remaining in their hand.\n・Send the top 3 cards of your deck to your discard pile.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_049.gd"
	},
	{
		"id": "EBP02-050",
		"name": "Mecha-King Ghidorah",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH, CardEnums.CardTrait.TWENTY_THIRD_CENTURY],
		"threat_level": 34000,
		"invasion_icon": 2,
		"description": "<Enter> If there are 5 or more cards under this card, choose one of the following:\n・ <Destroy> 3 of your opponent's rank 6 or lower battle cards.\n・Your opponent discards cards until they have 2 cards remaining in their hand.\n・Increase this card's <Rage> by 3.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_050.gd"
	},
	{
		"id": "EBP02-051",
		"name": "Mecha-King Ghidorah",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH, CardEnums.CardTrait.TWENTY_THIRD_CENTURY],
		"threat_level": 37000,
		"invasion_icon": 1,
		"description": "If there are 5 or more cards under this card, this card gains +3000 threat level for each of your opponent's unoccupied zones.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_051.gd"
	},
	{
		"id": "EBP02-052",
		"name": "SpaceGodzilla Flying Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.SPACEGODZILLA],
		"threat_level": 5000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_052.gd",
		"description": "<When Invading> You may discard 1 card from your hand, if you do, play 1 “Crystals” token. (Tokens are prepared separately from your deck.)"
	},
	{
		"id": "EBP02-053",
		"name": "SpaceGodzilla",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.SPACEGODZILLA],
		"threat_level": 12000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_053.gd",
		"description": "<When Invading> Play 1 “Crystals” token. (Tokens are prepared separately from your deck.)\nIf there is a “Crystals” in your zones, this card gains +5000 threat level."
	},
	{
		"id": "EBP02-054",
		"name": "SpaceGodzilla",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.SPACEGODZILLA],
		"threat_level": 20000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_054.gd",
		"description": "<Enter> Play 2 “Crystals” tokens. (Tokens are prepared separately from your deck.)\nWhenever this card's <Rage> is increased, <Destroy> 1 of your opponent's rank 5 or lower battle cards for each “Crystals” in your zones."
	},
	{
		"id": "EBP02-055",
		"name": "SpaceGodzilla",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.SPACEGODZILLA],
		"threat_level": 23000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_055.gd",
		"description": "<Awakening4> If there are 3 or more “Crystals” in your zones, your opponent cannot play battle cards in zones in the same column as this card. (Does not destroy cards already there.)"
	},
	{
		"id": "EBP02-056",
		"name": "SpaceGodzilla",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.SPACEGODZILLA],
		"threat_level": 32000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp02/ebp02_056.gd",
		"description": "If you have 3 or more “Crystals” in your zones, this card gains +20,000 threat level.\n<Your Turn> When this card advances during the end phase, it advances 1 additional zone for each “Crystals” in your zones."
	},
	{
		"id": "EBP02-057",
		"name": "SpaceGodzilla Flying Form",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.SPACEGODZILLA],
		"threat_level": 35000,
		"invasion_icon": 1,
		"description": "<Enter> Move 1 of your opponent's battle cards in the same column as this card to an unoccupied zone.\nWhenever this card's <Rage> is increased, play 2 “Crystals” tokens. (Tokens are prepared separately from your deck.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_057.gd"
	},
	{
		"id": "EBP02-058",
		"name": "Dorat",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.DORAT],
		"counter_power": 1000,
		"invasion_icon": 1,
		"description": "<Revenge> Return up to 1 <《King Ghidorah》> monster card from your discard pile to your hand. (Activates when destroyed by a card effect or monster card movement.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_058.gd"
	},
	{
		"id": "EBP02-059",
		"name": "Godzillasaurus",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GODZILLASAURUS],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "<Revenge> You may discard 1 card from your hand, if you do, return 1 battle card named “Godzilla(1991)” from your discard pile to your hand. (Activates when destroyed by a card effect or monster card movement.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_059.gd"
	},
	{
		"id": "EBP02-060",
		"name": "Gigan(2004)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.WEAPON, CardEnums.CardTrait.FINAL_WARS],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "If this card is in the same column as your opponent's monster card, this card gains +3000 counter power.\n<Revenge> If your opponent's monster card is in zones 1–5, you may return this card from your discard pile to your hand. (Activates when destroyed by a card effect or monster card movement.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_060.gd"
	},
	{
		"id": "EBP02-061",
		"name": "Godzilla(1972)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 4000,
		"invasion_icon": 2,
		"description": "If this card is in zone 8, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_061.gd"
	},
	{
		"id": "EBP02-062",
		"name": "SpaceGodzilla",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.SPACEGODZILLA],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Revenge> Return up to 1 <《SpaceGodzilla》> monster card from your discard pile to your hand. (Activates when destroyed by a card effect or monster card movement.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_062.gd"
	},
	{
		"id": "EBP02-063",
		"name": "Megalon",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MEGALON],
		"counter_power": 5000,
		"invasion_icon": 1
	},
	{
		"id": "EBP02-064",
		"name": "Gigan(1972)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GIGAN, CardEnums.CardTrait.WEAPON],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "If there is a card with <《King Ghidorah》> or <《Megalon》> in your zones, this card gains +3000 counter power.\n<Revenge> Return up to 1 <《King Ghidorah》> monster card from your discard pile to your hand. (Activates when destroyed by a card effect or monster movement.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_064.gd"
	},
	{
		"id": "EBP02-065",
		"name": "Godzilla(1991)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 5000,
		"invasion_icon": 2,
		"description": "<Awakening6> If there are 3 or more cards under your monster card, this card gains +5000 counter power. If there are 5 or more, this card gains an additional +5000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_065.gd"
	},
	{
		"id": "EBP02-066",
		"name": "King Ghidorah(1964)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"counter_power": 8000,
		"invasion_icon": 2,
		"description": "<Awakening6> This card gains +3000 counter power. (Active if your monster card is in zone 6 or beyond.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_066.gd"
	},
	{
		"id": "EBP02-067",
		"name": "M.O.G.U.E.R.A.",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MOGUERA, CardEnums.CardTrait.WEAPON],
		"counter_power": 10000,
		"invasion_icon": 2,
		"description": "If your opponent has a <《Godzilla》> card in their zones, this card gains +5000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_067.gd"
	},
	{
		"id": "EBP02-068",
		"name": "Mecha-King Ghidorah",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 23,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH, CardEnums.CardTrait.TWENTY_THIRD_CENTURY],
		"counter_power": 7000,
		"invasion_icon": 1,
		"description": "You can play this card from your hand with its rank reduced by 2 for each non-rank 23 <《King Ghidorah》> card in your discard pile. (This card's rank returns to 23 after being played.)\nIf this card is in the same column as your opponent's monster card, they cannot invade, and this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_068.gd"
	},
	{
		"id": "EBP02-069",
		"name": "Godzilla vs. SpaceGodzilla",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 1,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 1,
		"description": "Choose 2 of your opponent's battle cards in their zones and swap their positions.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_069.gd"
	},
	{
		"id": "EBP02-070",
		"name": "Godzilla vs. SpaceGodzilla",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp02/ebp02_070.gd",
		"description": "<Opponent's Turn> Your opponent cannot play strategy cards. (Does not destroy cards already in play.)\n<Opponent's Turn> At the beginning of the main phase, your opponent may discard cards until they have 5 cards remaining in their hand. If they discard at least 1 card, <Destroy> this card."
	},
	{
		"id": "EBP02-071",
		"name": "Godzilla vs. King Ghidorah",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 1,
		"description": "Choose one of the following:\n・ <Destroy> 3 of your opponent's rank 4 or lower battle cards.\n・ <Awakening6> <Destroy> 2 of your opponent's rank 6 or lower battle cards.\n・ <Awakening8> <Destroy> 1 of your opponent's battle cards.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_071.gd"
	},
	{
		"id": "EBP02-072",
		"name": "God of Destruction's Counterattack",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 5,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_072.gd",
		"description": "<Your Turn> If you have 3 or more “Crystals” in your zones, your total counter power is increased by 20,000."
	},
	{
		"id": "EBP02-073",
		"name": "Bloody Chainsaw",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 1,
		"description": "<Your Turn> Whenever you play a battle card, <Destroy> all of your opponent's rank 6 or lower battle cards in the same column as that battle card.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_073.gd"
	},
	{
		"id": "EBP02-074",
		"name": "Bite Attack",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 7,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 1,
		"description": "Increase your monster card's <Rage> by 1 for each rank of your opponent's monster.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_074.gd"
	},
	{
		"id": "EBP02-075",
		"name": "Chibi Mothra",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.CHIBI_GODZILLA_RAIDS_AGAIN, CardEnums.CardTrait.MOTHRA],
		"counter_power": 3000,
		"invasion_icon": 2,
		"description": "<Enter> If a card named “Chibi Mechagodzilla” is in your zones, reduce your opponent's <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_075.gd"
	},
	{
		"id": "EBP02-076",
		"name": "Chibi Mechagodzilla",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.CHIBI_GODZILLA_RAIDS_AGAIN, CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "If this card is in a zone adjacent to your monster card, this card gains +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_076.gd"
	},
	{
		"id": "EBP02-077",
		"name": "Chibi Godzilla",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.CHIBI_GODZILLA_RAIDS_AGAIN, CardEnums.CardTrait.GODZILLA],
		"counter_power": 5000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_077.gd",
		"description": "At the beginning of your main phase, send the top 2 cards of your deck to your discard pile.\nIf a <《Godzilla》> card was sent to your discard pile this way, <Destroy> this card and play a “Chibi Godzilla 2nd Form” token. (Tokens are prepared separately from your deck.)"
	},
	{
		"id": "EBP02-078",
		"name": "Mothra(imago)(2003)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 7000,
		"invasion_icon": 1,
		"description": "<Enter> If this card is in the same column as your opponent's monster card, reveal the top 2 cards of your deck. Add all rank 5 or lower battle cards among them to your hand and send the rest into your discard pile.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_078.gd"
	},
	{
		"id": "EBP02-079",
		"name": "Destructive Impulse",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 1,
		"description": "Perform the following action based on how many zones your monster card advanced through invasion this turn:\n\n0 - <Destroy> all of your opponent's rank 2 or lower battle cards.\n1 - <Destroy> all of your opponent's rank 4 or lower battle cards.\n2 - <Destroy> all of your opponent's rank 6 or lower battle cards.",
		"effect_script": "res://scripts/effects/ebp02/ebp02_079.gd"
	},
	{
		"id": "EBP02-080",
		"name": "Joint Struggle",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 1,
		"description": "Reveal the top 2 cards of your deck. If they differ in at least 1 trait, add them to your hand; otherwise, send them to the discard pile. (Example if one is <《Mech》> and the other is <《Mechagodzilla》> and <《Mech》> , you may add them to your hand.)",
		"effect_script": "res://scripts/effects/ebp02/ebp02_080.gd"
	},
	{
		"id": "EBP02-T01",
		"name": "Conductorless Train Bombers",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.TOKEN, CardEnums.CardTrait.WEAPON],
		"counter_power": 2000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_t01.gd",
		"description": "<Enter> Reduce your opponent's <Rage> by 1.\n(Tokens cannot be added to the deck. They are banished when removed from zones.)"
	},
	{
		"id": "EBP02-T02",
		"name": "Tentacles",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.TOKEN, CardEnums.CardTrait.BIOLLANTE],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "(Tokens cannot be added to the deck. They are banished when removed from zones.)"
	},
	{
		"id": "EBP02-T03",
		"name": "Crystals",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 1,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.TOKEN, CardEnums.CardTrait.CRYSTAL],
		"counter_power": 0,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_t03.gd",
		"description": "All of your <《SpaceGodzilla》> monster cards in your zones gain +1000 threat level.\n(Tokens cannot be added to the deck. They are banished when removed from zones.)"
	},
	{
		"id": "EBP02-T04",
		"name": "Chibi Godzilla 2nd Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.TOKEN, CardEnums.CardTrait.CHIBI_GODZILLA_RAIDS_AGAIN, CardEnums.CardTrait.GODZILLA],
		"counter_power": 10000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp02/ebp02_t04.gd",
		"description": "At the beginning of your end phase, <Destroy> this card and play 1 battle card named “Chibi Godzilla” from your discard pile.\n(Tokens cannot be added to the deck. They are banished when removed from zones.)"
	},
]

# --- EBP03: Booster Pack 03 ---
var EBP03_CARDS: Array[Dictionary] = [
	{
		"id": "EBP03-001",
		"name": "Godzilla(2001)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 4000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_001.gd",
		"description": "<Awakening4> At the beginning of your end phase, you may discard 1 rank 5 or higher battle card from your hand. If you do, this card advances 1 zone.\n<Awakening6> This card gains +5000 threat level."
	},
	{
		"id": "EBP03-002",
		"name": "Godzilla(2001)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 14000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp03/ebp03_002.gd",
		"description": "<Opponent’s Turn> <Awakening4> At the beginning of the counter phase, you may discard 1 rank 5 or higher battle card from your hand. If you do, increase this card’s <Rage> by 1.\n<Awakening8> At the beginning of your counter phase, you may discard 1 rank 5 or higher battle card from your hand. If you do, increase this card’s <Rage> by 2."
	},
	{
		"id": "EBP03-003",
		"name": "Godzilla(2001)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 22000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_003.gd",
		"description": "<Burst2> (You can play this card from rank II. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Awakening8> At the beginning of your counter phase, you may discard 1 rank 5 or higher battle card from your hand. If you do, increase this card’s <Rage> by 2, then <Destroy> all of your opponent’s rank 6 or lower battle cards. (Active if this card is in zone 8.)"
	},
	{
		"id": "EBP03-004",
		"name": "Godzilla(2001)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 35000,
		"invasion_icon": 1,
		"description": "When this card invades, you may send the top card of your deck to your discard pile instead of discarding a card from your hand.\n<Opponent's Turn> <Awakening4> This card's <Rage> cannot be reduced by your opponent's effects. (Active if this is in zone 4 or beyond.)",
		"effect_script": "res://scripts/effects/ebp03/ebp03_004.gd"
	},
	{
		"id": "EBP03-005",
		"name": "Godzilla(2001)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 36000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_005.gd",
		"description": "<Burst3> (You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Awakening8> At the beginning of your counter phase, you may discard 1 rank 5 or higher battle card from your hand. If you do, increase this card’s <Rage> by 3, then <Destroy> all of your opponent’s rank 7 or lower battle cards. (Active if this card is in zone 8.)"
	},
	{
		"id": "EBP03-006",
		"name": "Multi-purpose Fighting System-3",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED, CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"threat_level": 5000,
		"invasion_icon": 1,
		"resonance": {
			"main_monster_required_traits": [CardEnums.CardTrait.WEAPON, CardEnums.CardTrait.MECH],
			"main_battle_required_traits": [CardEnums.CardTrait.WEAPON, CardEnums.CardTrait.MECH],
		},
		"description": "<Resonance> Red/Blue\n・Monster cards in your deck must have <《Weapon》> or <《Mech》> .\n・Battle cards in your deck must have <《Weapon》> or <《Mech》> .\n(You can mix red, blue, and white, but your monster deck and main deck must satisfy the above.)"
	},
	{
		"id": "EBP03-007",
		"name": "Multi-purpose Fighting System-3",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED, CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"threat_level": 12000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp03/ebp03_007.gd",
		"description": "<When Invading> Reveal from the top of your deck a number of cards equal to the rank of your opponent’s monster card. Add 1 red or blue battle card among them to your hand, then send the rest to your discard pile."
	},
	{
		"id": "EBP03-008",
		"name": "Multi-purpose Fighting System-3",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED, CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"threat_level": 21000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_008.gd",
		"description": "<Enter> If there is a blue battle card in your zones, <Destroy> 1 of your opponent’s rank 5 or lower battle cards.\n<Opponent’s Turn> At the beginning of the counter phase, if there is a red battle card in your zones, <Destroy> 1 of your opponent’s rank 5 or lower battle cards in the same column as this card."
	},
	{
		"id": "EBP03-009",
		"name": "Multi-purpose Fighting System-3",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED, CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"threat_level": 37000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_009.gd",
		"description": "<Enter> Choose 1 of your opponent’s zones in the same column as this card, then <Destroy> all of your opponent’s rank 6 or lower battle cards in that zone and zones adjacent to it."
	},
	{
		"id": "EBP03-010",
		"name": "Multi-purpose Fighting System-3",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED, CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"threat_level": 22000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_010.gd",
		"description": "<Enter> If there are 2 or more battle cards in your zones, your opponent discards cards until they have 4 cards remaining in their hand. If a battle card is discarded this way, increase this card’s <Rage> by 1."
	},
	{
		"id": "EBP03-011",
		"name": "Multi-purpose Fighting System-3",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED, CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"threat_level": 33000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_011.gd",
		"description": "<Burst3> (You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> Reveal from the top of your deck a number of cards equal to the rank of your opponent’s monster card. Add up to 1 red battle card and up to 1 blue battle card among them to your hand, then send the rest to your discard pile."
	},
	{
		"id": "EBP03-012",
		"name": "Godzilla(1993)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 12000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_012.gd",
		"description": "<Enter> If you have 1 or fewer strategy cards in play, you may place up to 1 blue rank 6 or lower strategy card from your hand into your strategy zone and activate it."
	},
	{
		"id": "EBP03-013",
		"name": "Godzilla(1995)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 50000,
		"invasion_icon": 1,
		"description": "<Enter> For the rest of the game, you have 3 strategy card zones. (It remains 3 even if this leaves play.)\n<Opponent's Turn> At the beginning of the counter phase, if there are no cards in your strategy zones, you lose the game.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_013.gd"
	},
	{
		"id": "EBP03-014",
		"name": "Godzilla(2002)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 5000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_014.gd",
		"description": "At the beginning of your end phase, you may discard 1 battle card from your hand. If you do, draw 1 card."
	},
	{
		"id": "EBP03-015",
		"name": "Godzilla(2002)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 9000,
		"invasion_icon": 1,
		"description": "Whenever you discard a battle card from your hand, reduce your opponent's <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_015.gd"
	},
	{
		"id": "EBP03-016",
		"name": "Godzilla(2003)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 17000,
		"invasion_icon": 2,
		"description": "Whenever you discard a battle card from your hand, reduce your opponent's <Rage> by 1. If your opponent's <Rage> is 0, increase this card's <Rage> by 1 instead.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_016.gd"
	},
	{
		"id": "EBP03-017",
		"name": "Godzilla(2003)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 29000,
		"invasion_icon": 1,
		"description": "Whenever you discard a battle card from your hand, reduce your opponent's <Rage> by 1. If your opponent's <Rage> is 0, increase this card's <Rage> by 1 instead.\n<Enter> You may discard 1 battle card from your hand. If you do, <Destroy> 1 of your opponent's rank 6 or lower battle cards.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_017.gd"
	},
	{
		"id": "EBP03-018",
		"name": "Mothra(imago)(1996)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE, CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"threat_level": 5000,
		"invasion_icon": 1,
		"resonance": {
			"main_monster_required_traits": [CardEnums.CardTrait.MOTHRA],
			"main_strategy_min_count": 10,
		},
		"description": "<Resonance> Blue/Green\n・Monster cards in your deck must have <《Mothra》> .\n・Your deck must contain at least 10 strategy cards.\n(You can mix blue, green, and white, but your monster deck and main deck must satisfy the above.)"
	},
	{
		"id": "EBP03-019",
		"name": "Mothra(larva)(1996)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE, CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"threat_level": 14000,
		"invasion_icon": 2,
		"description": "When you successfully counter your opponent's monster card, if you have a card with <Base> in play, increase this card's <Rage> by 2.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_019.gd"
	},
	{
		"id": "EBP03-020",
		"name": "Mothra Leo",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE, CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"threat_level": 23000,
		"invasion_icon": 1,
		"description": "When you successfully counter your opponent's monster card, if you have a card with <Base> in play, <Destroy> 1 opponent's rank 7 or lower battle card.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_020.gd"
	},
	{
		"id": "EBP03-021",
		"name": "Rainbow Mothra",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE, CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"threat_level": 22000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_021.gd",
		"description": "<Enter> Return 1 strategy card with <Base> from your discard pile to your hand."
	},
	{
		"id": "EBP03-022",
		"name": "Aqua Mothra",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE, CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"threat_level": 34000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_022.gd",
		"description": "If you have a card with <Base> in play, this card gains +10,000 threat level."
	},
	{
		"id": "EBP03-023",
		"name": "Armor Mothra",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE, CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"threat_level": 31000,
		"invasion_icon": 1,
		"description": "<Enter> Evolve all of your <《Mothra》> battle cards with <Evolution> .\nWhen you successfully counter your opponent's monster card, if you have a card with <Base> in play, retreat your opponent's monster card back to zone 1.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_023.gd"
	},
	{
		"id": "EBP03-024",
		"name": "Baragon(2001)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.GREEN, CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.BARAGON, CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS],
		"threat_level": 5000,
		"invasion_icon": 1,
		"resonance": {
			"main_monster_required_traits": [CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS],
			"main_battle_min_rank": 5,
		},
		"description": "<Resonance> Green/Red\n・Monster cards in your deck must have <《Sacred Guardian Beasts》> .\n・Battle cards in your deck must be Rank 5 or higher.\n(You can mix green, red, and white, but your monster deck and main deck must satisfy the above.)"
	},
	{
		"id": "EBP03-025",
		"name": "Mothra(imago)(2001)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.GREEN, CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MOTHRA, CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS],
		"threat_level": 11000,
		"invasion_icon": 1,
		"description": "<Your Turn> Reduce the rank of all battle cards in your opponent's zones by 1.\n<Enter> You may place 1 monster card from your discard pile under this card. If you do, advance your opponent's monster card to zone 5.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_025.gd"
	},
	{
		"id": "EBP03-026",
		"name": "Mothra(imago)(2001)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN, CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MOTHRA, CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS],
		"threat_level": 19000,
		"invasion_icon": 1,
		"description": "<Your Turn> If there are 3 or more cards under this card, reduce the rank of all battle cards in your opponent's zones by 2.\n<Enter> You may place 2 monster cards from your discard pile under this card. If you do, reduce your opponent's <Rage> by 1.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_026.gd"
	},
	{
		"id": "EBP03-027",
		"name": "Ghidorah(2001)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN, CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GHIDORAH, CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS],
		"threat_level": 23000,
		"invasion_icon": 1,
		"description": "<Your Turn> If there are 3 or more cards under this card, reduce the rank of all battle cards in your opponent's zones by 2.\n<When Invading> If there are 5 or more cards under this card, your opponent discards cards until they have 4 cards remaining in their hand.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_027.gd"
	},
	{
		"id": "EBP03-028",
		"name": "Thousand-Year Dragon King Ghidorah",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN, CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH, CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS],
		"threat_level": 32000,
		"invasion_icon": 2,
		"description": "<Your Turn> If there are 5 or more cards under this card, reduce the rank of all battle cards in your opponent's zones by 3.\n<Opponent's Turn> At the beginning of the counter phase, you may place 3 monster cards from your discard pile under this card. If you do, <Destroy> all rank 5 or lower battle cards in your opponent's zones 1–5.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_028.gd"
	},
	{
		"id": "EBP03-029",
		"name": "Thousand-Year Dragon King Ghidorah",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN, CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH, CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS],
		"threat_level": 35000,
		"invasion_icon": 1,
		"description": "<Your Turn> If there are 5 or more cards under this card, reduce the rank of all battle cards in your opponent's zones by 3.\n<When Invading> If there are 7 or more cards under this card, choose one:\n・ <Destroy> all battle cards of both players.\n・Each player discards cards until they have 2 cards remaining in their hand.\n・Reduce each player's monster card's <Rage> by 2.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_029.gd"
	},
	{
		"id": "EBP03-030",
		"name": "SHIRASAGI : AC-3",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.WEAPON],
		"counter_power": 0,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_030.gd",
		"description": "Your <《Mechagodzilla》> battle cards in your zone 8 gain +3000 counter power.\n<Enter> You may move 1 other battle card in your zones to an unoccupied zone."
	},
	{
		"id": "EBP03-031",
		"name": "MBT-MB90",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.WEAPON],
		"counter_power": 1000,
		"invasion_icon": 1,
		"unlimited_copies": true,
		"effect_script": "res://scripts/effects/ebp03/ebp03_031.gd",
		"description": "You may have any number of this card in your deck.\n<Enter> Look at the top card of your deck. You may send it to your discard pile or place it back on top of your deck."
	},
	{
		"id": "EBP03-032",
		"name": "Mechagodzilla(1974)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 3000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_032.gd",
		"description": "At the beginning of your counter phase, if this card is in a zone adjacent to your monster card, you may discard all the cards in your hand. If you do, for the rest of the turn, this card gains +1000 counter power for each card discarded this way."
	},
	{
		"id": "EBP03-033",
		"name": "Mechagodzilla(1975)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 2000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_033.gd",
		"description": "<Enter> You may discard 1 rank 5 or higher battle card from your hand. If you do, search your deck for up to 1 card named “Space Beam”, reveal it, add it to your hand, then shuffle your deck."
	},
	{
		"id": "EBP03-034",
		"name": "Jet Jaguar(1973)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.JET_JAGUAR, CardEnums.CardTrait.MECH],
		"counter_power": 4000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_034.gd",
		"description": "<Enter> You may discard 1 strategy card from your hand. If you do, reduce your opponent’s <Rage> by 1."
	},
	{
		"id": "EBP03-035",
		"name": "Satsuma",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.WEAPON],
		"counter_power": 5000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp03/ebp03_035.gd",
		"description": "<Enter> If this card is in the same column as your opponent’s monster card, you may discard 1 strategy card from your hand. If you do, advance your monster card to zone 6."
	},
	{
		"id": "EBP03-036",
		"name": "Moguera",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MOGUERA, CardEnums.CardTrait.WEAPON],
		"counter_power": 4000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp03/ebp03_036.gd",
		"description": "<Enter> If this card was played from your hand and is in zone 8, search your deck for up to 1 ⁅《モゲラ》＠⁆ battle card, play it, then shuffle your deck."
	},
	{
		"id": "EBP03-037",
		"name": "Godzilla(2001)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 5000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_037.gd",
		"description": "<Awakening8> <Enter> Increase your monster card’s <Rage> by 1.\n<Awakening8> This card gains +5000 counter power."
	},
	{
		"id": "EBP03-038",
		"name": "Multi-purpose Fighting System-3",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 8000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_038.gd",
		"description": "At the beginning of your counter phase, if your opponent has 2 or more <Rage> , <Destroy> all of your battle cards in zones adjacent to this card."
	},
	{
		"id": "EBP03-039",
		"name": "Godzilla(2016) 4th Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA, CardEnums.CardTrait.FOURTH_FORM],
		"counter_power": 5000,
		"invasion_icon": 2,
		"description": "Whenever your card is sent from a strategy zone to the discard pile, draw 1 card. (Also triggers when a strategy card is destroyed)\nIf there are 5 or more strategy cards in your discard pile, this card gains +5000 counter power.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_039.gd"
	},
	{
		"id": "EBP03-040",
		"name": "Mechagodzilla(1975)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 6000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_040.gd",
		"description": "At the beginning of your counter phase, you may move this card to an unoccupied zone.\nIf this is in the same column as your opponent’s monster card, this card gains +3000 counter power."
	},
	{
		"id": "EBP03-041",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 11000,
		"invasion_icon": 1,
		"description": "<Enter> If this is in the same column as your opponent's monster card and your monster card has 2 or more <Rage> , reduce your opponent's <Rage> by 2.\nWhen this card would be <Destroy> , put this card on the bottom of your deck instead.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_041.gd"
	},
	{
		"id": "EBP03-042",
		"name": "Ghogo",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GHOGO],
		"counter_power": 1000,
		"invasion_icon": 1,
		"description": "When your monster card invades, if this is in zone 8, you may put this card under one of your <《Mothra》> battle cards with <Evolution> . If you do, evolve that <《Mothra》> battle card.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_042.gd"
	},
	{
		"id": "EBP03-043",
		"name": "Star Falcon",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.WEAPON],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "<Awakening4> At the beginning of your counter phase, you may place this card under a card named \"Land Moguera\" in your zones. If you do, search your deck for up to 1 Moguera battle card, play it on top of the card named \"Land Moguera\" you chose for this effect, then shuffle your deck. (Active if your monster card is in zone 4 or beyond.)",
		"effect_script": "res://scripts/effects/ebp03/ebp03_043.gd"
	},
	{
		"id": "EBP03-044",
		"name": "Mothra(larva)(1992)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 3000,
		"invasion_icon": 2,
		"evolution_rank": 7,
		"evolution_trait": CardEnums.CardTrait.MOTHRA,
		"description": "<Evolution7> <《Mothra》> (At the beginning of your main phase, you may play a rank 7 or lower <《Mothra》> battle card from your deck by placing it on top of this card.)",
		"effect_script": "res://scripts/effects/ebp03/ebp03_044.gd"
	},
	{
		"id": "EBP03-045",
		"name": "Mothra(larva)(2003)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 2000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_045.gd",
		"description": "If this card is in a zone adjacent to your monster card, this card gains +3000 counter power."
	},
	{
		"id": "EBP03-046",
		"name": "Land Moguera",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.WEAPON],
		"counter_power": 3000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_046.gd",
		"description": "<Awakening4> <Enter> If “Star Falcon” is in your zones, choose one:\n・ <Destroy> 1 of your opponent’s strategy cards.\n・Reduce your opponent’s <Rage> by 1."
	},
	{
		"id": "EBP03-047",
		"name": "Garuda",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.WEAPON],
		"counter_power": 4000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp03/ebp03_047.gd",
		"description": "At the beginning of your counter phase, if this card is in the same column as your opponent’s monster card, you may discard 1 battle card with <《Weapon》> or <《Mech》> from your hand. If you do, search your deck for up to 1 battle card named “Super Mechagodzilla”, play it on top of this card, then shuffle your deck."
	},
	{
		"id": "EBP03-048",
		"name": "Mechagodzilla(1993)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 4000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_048.gd",
		"description": "<Enter> If there are 2 or more other battle cards in your zones, reduce your opponent’s <Rage> by 1."
	},
	{
		"id": "EBP03-049",
		"name": "Godzilla(2002)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 5000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_049.gd",
		"description": "<Enter> If this card is in zone 8, draw 2 cards, then discard 2 cards."
	},
	{
		"id": "EBP03-050",
		"name": "Rainbow Mothra",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 6000,
		"invasion_icon": 1,
		"evolution_rank": 8,
		"evolution_trait": CardEnums.CardTrait.MOTHRA,
		"effect_script": "res://scripts/effects/ebp03/ebp03_050.gd",
		"description": "<Enter> If you have a card with <Base> in play, an opponent’s monster card with 20,000 or less threat level retreats backward by 1 zone.\n<Evolution8> <《Mothra》> (At the beginning of your main phase, you may play a rank 8 or lower <《Mothra》> battle card from your deck by placing it on top of this card.)"
	},
	{
		"id": "EBP03-051",
		"name": "Godzilla Jr.",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA_JR],
		"counter_power": 6000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp03/ebp03_051.gd",
		"description": "If you would play this card on top of your <《Little Godzilla》> battle card, you may play this from your hand with its rank reduced by 2. (After being played, this card is rank 7.)\nThis card gains +5000 counter power for each card under it."
	},
	{
		"id": "EBP03-052",
		"name": "M.O.G.U.E.R.A.",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MOGUERA, CardEnums.CardTrait.WEAPON],
		"counter_power": 7000,
		"invasion_icon": 2,
		"description": "When this card would be <Destroy> by an opponent's effect, add all cards under this card to your hand.\n<Awakening6> <Enter> If there are no cards under this card, search your deck for up to 1 card named \"Land Moguera\" and up to 1 card named \"Star Falcon\", place them under this card, then shuffle your deck.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_052.gd"
	},
	{
		"id": "EBP03-053",
		"name": "Super Mechagodzilla",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 8000,
		"invasion_icon": 1,
		"description": "While your opponent's <Rage> is 0, this card cannot be <Destroy> by opponent's effects.\nIf this card is in the same column as your opponent's monster card, this card gains +3000 counter power for each of your opponent's <Rage> .",
		"effect_script": "res://scripts/effects/ebp03/ebp03_053.gd"
	},
	{
		"id": "EBP03-054",
		"name": "Eternal Mothra",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 10000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_054.gd",
		"description": "<Enter> If this card is in zone 8 and you have a card with <Base> in play, an opponent’s monster card with 60,000 or less threat level retreats backward by 1 zone."
	},
	{
		"id": "EBP03-055",
		"name": "Primitive Mothra",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 2000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_055.gd",
		"description": "<Enter> You may put up to 1 <《Mothra》> battle card from your discard pile on top of your deck."
	},
	{
		"id": "EBP03-056",
		"name": "Manda(2004)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MANDA, CardEnums.CardTrait.FINAL_WARS],
		"counter_power": 2000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_056.gd",
		"description": "If this card is in the same column as your opponent’s monster card, this card gains +3000 counter power."
	},
	{
		"id": "EBP03-057",
		"name": "Desghidorah",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.DESGHIDORAH],
		"counter_power": 2000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_057.gd",
		"description": "<Enter> If your opponent has 3 or more unoccupied zones, <Destroy> 1 of your opponent’s strategy cards.\nIf your opponent has no strategy cards in play, this card gains +3000 counter power."
	},
	{
		"id": "EBP03-058",
		"name": "Zilla",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.ZILLA, CardEnums.CardTrait.FINAL_WARS],
		"counter_power": 5000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_058.gd",
		"description": "At the beginning of your end phase, move this card to an adjacent zone horizontal to the zone this card currently occupies. Then, if this card is in a zone adjacent to your monster card, <Destroy> this card.."
	},
	{
		"id": "EBP03-059",
		"name": "Cretaceous King Ghidorah(1998)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"counter_power": 3000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_059.gd",
		"description": "<Revenge> Return up to 1 <《King Ghidorah》> monster card from your discard pile to your hand. (Activates when destroyed by a card effect or monster card movement.)"
	},
	{
		"id": "EBP03-060",
		"name": "Mothra(imago)(1961)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 5000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp03/ebp03_060.gd",
		"description": "<Revenge> Reduce your opponent’s <Rage> by 1. (Activates when destroyed by a card effect or monster card movement.)"
	},
	{
		"id": "EBP03-061",
		"name": "Dagahra",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.DAGAHRA],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "When you discard this card from your hand for your monster card's invasion, you may play this card from your discard pile.\n<Awakening6> This card gains +3000 counter power. (Active if your monster card is in zone 6 or beyond.)",
		"effect_script": "res://scripts/effects/ebp03/ebp03_061.gd"
	},
	{
		"id": "EBP03-062",
		"name": "Baragon(2001)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.BARAGON, CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "When your opponent's monster card invades, <Destroy> this card.\n<Revenge> Return up to 1 ⁅《護国聖獣》＠⁆ monster card from your discard pile to your hand. (Activates when destroyed by a card effect or monster card movement.)",
		"effect_script": "res://scripts/effects/ebp03/ebp03_062.gd"
	},
	{
		"id": "EBP03-063",
		"name": "King Ghidorah(1998)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"counter_power": 6000,
		"invasion_icon": 2,
		"description": "<Your Turn> <Awakening4> When your monster card is played, you may play this card from your discard pile. (Active if your monster card is in zone 4 or beyond.)",
		"effect_script": "res://scripts/effects/ebp03/ebp03_063.gd"
	},
	{
		"id": "EBP03-064",
		"name": "Mothra(imago)(2001)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.MOTHRA, CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS],
		"counter_power": 6000,
		"invasion_icon": 1,
		"description": "<Enter> If an opponent's battle card was <Destroy> this turn, you may place 1 battle card from your discard pile under this card.\n<Awakening4> If there is a card under this card, this card gains +3000 counter power.\n<Awakening6> If there is a card under this card, this card gains an additional +3000 counter power.",
		"effect_script": "res://scripts/effects/ebp03/ebp03_064.gd"
	},
	{
		"id": "EBP03-065",
		"name": "King Ghidorah(1998)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH],
		"counter_power": 7000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_065.gd",
		"description": "If there are 5 or more cards under your monster card, this card gains +3000 counter power."
	},
	{
		"id": "EBP03-066",
		"name": "Thousand-Year Dragon King Ghidorah",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.GREEN],
		"traits": [CardEnums.CardTrait.KING_GHIDORAH, CardEnums.CardTrait.SACRED_GUARDIAN_BEASTS],
		"counter_power": 9000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_066.gd",
		"description": "If your opponent has 2 or more strategy cards in play, you may play this card from your hand with its rank reduced by 2. (After being played, this card is rank 8.)\n<Enter> <Destroy> 1 of your opponent’s strategy cards."
	},
	{
		"id": "EBP03-067",
		"name": "Monster X",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.WHITE],
		"traits": [CardEnums.CardTrait.MONSTER_X, CardEnums.CardTrait.FINAL_WARS],
		"counter_power": 0,
		"counter_power_variable": true,
		"invasion_icon": 1,
		"description": "<Your Turn> When this card is discarded from your hand, if there are 2 or more colors among battle cards in your zones, play this card and <Destroy> up to 1 of your opponent's lowest ranked battle cards in their zones.\nThis card's counter power X is equal to 3000 multiplied by the number of different colors among other battle cards in your zones. (White also counts as a color.)",
		"effect_script": "res://scripts/effects/ebp03/ebp03_067.gd"
	},
	{
		"id": "EBP03-068",
		"name": "Godzilla Flies",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 2,
		"description": "<Your Turn> Your monster card cannot invade.\nMove your rank III or higher monster card in zone 3 vertically to zone 8. (Your battle cards in zones 4–7 will not be <Destroy> by this movement.)",
		"effect_script": "res://scripts/effects/ebp03/ebp03_068.gd"
	},
	{
		"id": "EBP03-069",
		"name": "Space Beam",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_069.gd",
		"description": "Your opponent discards cards until they have 4 cards remaining in their hand. Then, if there is a <《Mechagodzilla》> card in your zone 8, <Destroy> all opponent’s rank 5 or lower battle cards."
	},
	{
		"id": "EBP03-070",
		"name": "Mechagodzilla Hangar",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 5,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_070.gd",
		"is_base": true,
		"description": "<Base> When any monster card invades into zones 6–8, <Destroy> this card. (Cards with Base are not sent to the discard pile at the start phase.)\n<Your Turn> At the beginning of your counter phase, search your deck for up to 1 battle card with <《Weapon》> or <《Mech》> , reveal it, add it to your hand, then shuffle your deck."
	},
	{
		"id": "EBP03-071",
		"name": "Godzilla's Skeleton",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 8,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"description": "When counting monster cards in your discard pile, treat this card as a monster card as well.\nLook at the top 4 cards of your deck, put any number of them on top of your deck in any order, send the rest to your discard pile, then draw 2 cards.",
		"counts_as_monster_in_discard": true,
		"effect_script": "res://scripts/effects/ebp03/ebp03_071.gd"
	},
	{
		"id": "EBP03-072",
		"name": "Petit Railgun",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_072.gd",
		"description": "[Destroy] all of your opponent's battle cards in the same column as your monster card."
	},
	{
		"id": "EBP03-073",
		"name": "All-Weapon Attack",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp03/ebp03_073.gd",
		"description": "Reveal the top 3 cards of your deck and send them to your discard pile; <Destroy> all of your opponent’s battle cards in zones whose numbers match the ranks of the revealed cards, if your opponent's monster card occupies 1 of those zones, your opponent’s monster card retreats backward by 1 zone."
	},
	{
		"id": "EBP03-074",
		"name": "A Journey of 130 Million Years",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 1,
		"description": "If your monster card is rank III or lower, play 1 monster card from your monster deck that shares a trait with it, whose its rank is 1 higher than your monster card's current rank. (This play does not increase <Rage> .)",
		"effect_script": "res://scripts/effects/ebp03/ebp03_074.gd"
	},
	{
		"id": "EBP03-075",
		"name": "Yakusugi",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_075.gd",
		"is_base": true,
		"description": "<Base> When any monster card invades into zones 6–8, <Destroy> this card. (Cards with Base are not sent to the discard pile at the start phase.)\n<Your Turn> At the beginning of your counter phase, evolve 1 of your rank 4 or lower battle cards with <Evolution> ."
	},
	{
		"id": "EBP03-076",
		"name": "The Battle at Fukuoka Tower",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_076.gd",
		"is_base": true,
		"description": "<Base> When any monster card invades into zones 6–8, <Destroy> this card. (Cards with Base are not sent to the discard pile at the start phase.)\n<Opponent’s Turn> For each monster or battle card in your zones 1, 5, and 8, your monster card gains +5000 threat level."
	},
	{
		"id": "EBP03-077",
		"name": "Rebirth of Mothra 3",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/ebp03/ebp03_077.gd",
		"description": "Choose one:\n・Return 1 rank II or lower monster card from your discard pile to your hand.\n・If there are 5 or more cards under your monster card, return 1 monster card from your discard pile to your hand."
	},
	{
		"id": "EBP03-078",
		"name": "Megalon and Gigan:Villain Tag Team",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 5,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_078.gd",
		"description": "If there are 3 or more battle cards in your opponent’s zones, <Destroy> 1 battle card from the rightmost and 1 from the leftmost position from among them (from your perspective)."
	},
	{
		"id": "EBP03-079",
		"name": "Godzilla Captured!",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 7,
		"colors": [CardEnums.CardColor.GREEN],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_079.gd",
		"description": "Set your opponent’s <Rage> to 0."
	},
	{
		"id": "EBP03-080",
		"name": "Odo Island",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/ebp03/ebp03_080.gd",
		"is_base": true,
		"description": "<Base> When any monster card invades into zones 6–8, <Destroy> this card. (Cards with Base are not sent to the discard pile at the start phase.)\n<Your Turn> At the beginning of your counter phase, you may play up to 1 <《Godzilla》> battle card from your hand."
	},
]

# --- EPR: Promo Cards ---
var EPR_CARDS: Array[Dictionary] = [
	{
		"id": "EPR-005",
		"name": "Godzilla's Bite",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"description": "<Destroy> all of your opponent's battle cards in the same column as your monster card.",
		"effect_script": "res://scripts/effects/epr/epr_005.gd"
	},
]

# --- ESD01: Starter Deck 01 - Godzilla Minus One ---
var ESD01_CARDS: Array[Dictionary] = [
	{
		"id": "ESD01-001",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 6000,
		"invasion_icon": 1
	},
	{
		"id": "ESD01-002",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 8000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_002.gd",
		"description": "<When Invading> Search your deck for up to 1 rank Ⅲ card named 「Godzilla(2023)」 with <Burst> , reveal it, add it to your hand, then shuffle your deck. (If you invaded 2 zones, activate this effect 2 times)"
	},
	{
		"id": "ESD01-003",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 23000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_003.gd",
		"description": "If this card has 2 or more <Rage> , this card gains +5000 threat level."
	},
	{
		"id": "ESD01-004",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 38000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/esd01/esd01_004.gd",
		"description": "<When Invading> If this card has 2 or more <Rage> , your opponent discards cards until they have 2 cards remaining in their hand."
	},
	{
		"id": "ESD01-005",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 12000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_005.gd",
		"description": "<Burst1> (You can play this card from rank I. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> Your opponent discards cards until they have 4 cards remaining in their hand."
	},
	{
		"id": "ESD01-006",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 23000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_006.gd",
		"description": "<Burst2> (You can play this card from rank II. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> <Destroy> 1 of your opponent's rank 4 or lower battle cards."
	},
	{
		"id": "ESD01-007",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 38000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/esd01/esd01_007.gd",
		"description": "<Burst3> (You can play this card from rank III. If you do, send this card to your discard pile at the beginning of your next end phase.)\n<Enter> <Destroy> all of your opponent's battle cards in the same column as this card."
	},
	{
		"id": "ESD01-008",
		"name": "Shinseimaru",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.BOAT],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "(Battle cards in your hand can be played if their rank is equal to or lower than the number in the zone where the opponent's monster card is.)"
	},
	{
		"id": "ESD01-009",
		"name": "Reinforcements",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.BOAT],
		"counter_power": 2000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_009.gd",
		"description": "<Awakening4> This card gains +3000 counter power. (Active if your monster card is in zone 4 or beyond.)"
	},
	{
		"id": "ESD01-010",
		"name": "City of Tokyo",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.CITY],
		"counter_power": 0,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_010.gd",
		"description": "If your monster card has 2 or more <Rage> , your other battle card in zone 8 gains +5000 counter power.\n<Awakening6> Your other battle card in zone 8 gains +5000 counter power. (Active if your monster card is in zone 6 or beyond.)"
	},
	{
		"id": "ESD01-011",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 3000,
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_011.gd",
		"description": "<Enter> If your monster card has 2 or more <Rage> , reduce your opponent's <Rage> by 1.\nWhen this card is <Destroy> , place this card on the bottom of your deck instead."
	},
	{
		"id": "ESD01-012",
		"name": "Godzilla(2023)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.RED],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"counter_power": 7000,
		"invasion_icon": 2,
		"effect_script": "res://scripts/effects/esd01/esd01_012.gd",
		"description": "<Your Turn> When you play a monster card, you may move this card to an unoccupied zone.\nIf this card is in zone 8, this card gains +3000 counter power.\nWhen this card is <Destroy> , place this card on the bottom of your deck instead."
	},
	{
		"id": "ESD01-013",
		"name": "Ginza Annihilated",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 4,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_013.gd",
		"description": "<Your Turn> Whenever your monster card's <Rage> is increased, <Destroy> 1 of your opponent's rank 6 or lower battle cards."
	},
	{
		"id": "ESD01-014",
		"name": "Godzilla Emerges",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 6,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_014.gd",
		"description": "If your monster card has 2 or more <Rage> , search your deck for up to 1 battle card named 「Godzilla(2023)」, play it, then shuffle your deck."
	},
	{
		"id": "ESD01-015",
		"name": "Operation Wadatsumi",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 7,
		"colors": [CardEnums.CardColor.RED],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_015.gd",
		"description": "Your opponent discards cards until they have 2 cards remaining in their hand."
	},
	{
		"id": "ESD01-016",
		"name": "Heat Ray",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 1,
		"colors": [CardEnums.CardColor.WHITE],
		"invasion_icon": 1,
		"effect_script": "res://scripts/effects/esd01/esd01_016.gd",
		"description": "<Destroy> all of your opponent's battle cards in the same column as your monster card."
	},
]

# --- ESD02: Starter Deck 02 - Godzilla vs. Mechagodzilla ---
var ESD02_CARDS: Array[Dictionary] = [
	{
		"id": "ESD02-001",
		"name": "Godzilla(1984)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 1,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 6000,
		"invasion_icon": 1
	},
	{
		"id": "ESD02-002",
		"name": "Godzilla(1989)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 15000,
		"invasion_icon": 2,
		"description": "<Enter> <Destroy> 1 of your opponent's rank 4 or lower battle cards.",
		"effect_script": "res://scripts/effects/esd02/esd02_002.gd"
	},
	{
		"id": "ESD02-003",
		"name": "Godzilla(1992)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 18000,
		"invasion_icon": 1,
		"description": "<Enter> :Play 2 rank 4 or lower battle cards with <Evolution> from your discard pile in zones adjacent to this card.\n(For example, if this card is in zone 7, the adjacent zones are 4, 6, and 8.)",
		"effect_script": "res://scripts/effects/esd02/esd02_003.gd"
	},
	{
		"id": "ESD02-004",
		"name": "Godzilla(1994)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 35000,
		"invasion_icon": 1,
		"description": "<When Invading> Discard 1 battle card from your hand： <Destroy> all of your opponent's battle cards with a rank equal to or lower than the discarded card's rank.",
		"effect_script": "res://scripts/effects/esd02/esd02_004.gd"
	},
	{
		"id": "ESD02-005",
		"name": "Godzilla(1993)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 20000,
		"invasion_icon": 1,
		"description": "<When Invading> Reduce your opponent's <Rage> by 1. (If you invaded 2 zones, activate this effect 2 times.)",
		"effect_script": "res://scripts/effects/esd02/esd02_005.gd"
	},
	{
		"id": "ESD02-006",
		"name": "Godzilla(1995)",
		"card_type": CardEnums.CardType.MONSTER,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.GODZILLA],
		"threat_level": 36000,
		"invasion_icon": 1,
		"description": "For each strategy card your opponent has in play, this card gains +5000 threat level.",
		"effect_script": "res://scripts/effects/esd02/esd02_006.gd"
	},
	{
		"id": "ESD02-007",
		"name": "Mothra(larva)(1992)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 2,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 1000,
		"invasion_icon": 1,
		"description": "<Evolution5> <《Mothra》> At the beginning of your main phase, you may search your deck for a rank 5 or lower <《Mothra》> battle card and play it by stacking it on top of this card. Search for 「Mothra(imago)(1992)」 rank 5 counter power 5000 and you may place it on top of this card)",
		"effect_script": "res://scripts/effects/esd02/esd02_007.gd",
		"evolution_rank": 5,
		"evolution_trait": CardEnums.CardTrait.MOTHRA
	},
	{
		"id": "ESD02-008",
		"name": "Battra(larva)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 3,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BATTRA],
		"counter_power": 2000,
		"invasion_icon": 1,
		"description": "<Evolution6> <《Battra》> (At the beginning of your main phase, you may search your deck for a rank 6 or lower <《Battra》> battle card and play it by stacking it on top of this card. Search for 「Battra(imago)」 rank 6 counter power 5000 and you may place it on top of this card.)",
		"effect_script": "res://scripts/effects/esd02/esd02_008.gd",
		"evolution_rank": 6,
		"evolution_trait": CardEnums.CardTrait.BATTRA
	},
	{
		"id": "ESD02-009",
		"name": "Super-X",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 4,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.SUPER_X, CardEnums.CardTrait.WEAPON],
		"counter_power": 3000,
		"invasion_icon": 1,
		"description": "<Awakening4> <Enter> If this card is in zone 8, reduce your opponent's <Rage> by 1. (Active if your monster card is in zone 4 or beyond and this card was played in zone 8.)",
		"effect_script": "res://scripts/effects/esd02/esd02_009.gd"
	},
	{
		"id": "ESD02-010",
		"name": "Mothra(imago)(1992)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MOTHRA],
		"counter_power": 5000,
		"invasion_icon": 2,
		"description": "<Enter> If this card was played through evolution, draw 1 card.",
		"effect_script": "res://scripts/effects/esd02/esd02_010.gd"
	},
	{
		"id": "ESD02-011",
		"name": "Battra(imago)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 6,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.BATTRA],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "<Awakening6> This card gains ＋3000 counter power. (Active if your monster card is in zone 6 or beyond.)",
		"effect_script": "res://scripts/effects/esd02/esd02_011.gd"
	},
	{
		"id": "ESD02-012",
		"name": "Mechagodzilla(1993)",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.MECHAGODZILLA, CardEnums.CardTrait.WEAPON],
		"counter_power": 5000,
		"invasion_icon": 1,
		"description": "If your opponent's monster card is rank IV or higher, this card gains +5000 counter power.\nIf this card is in the same column as your opponent's monster card, this card gains +3000 counter power.\n(If both conditions are met, this card gains +8000 counter power.)",
		"effect_script": "res://scripts/effects/esd02/esd02_012.gd"
	},
	{
		"id": "ESD02-013",
		"name": "Destoroyah Perfect Form",
		"card_type": CardEnums.CardType.BATTLE,
		"rank": 8,
		"colors": [CardEnums.CardColor.BLUE],
		"traits": [CardEnums.CardTrait.DESTOROYAH],
		"counter_power": 13000,
		"invasion_icon": 2
	},
	{
		"id": "ESD02-014",
		"name": "The Legend of Infant Island",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 5,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 2,
		"description": "Evolve 1 of your battle cards with <Evolution> .",
		"effect_script": "res://scripts/effects/esd02/esd02_014.gd"
	},
	{
		"id": "ESD02-015",
		"name": "Burning Godzilla's Rampage",
		"card_type": CardEnums.CardType.STRATEGY,
		"rank": 7,
		"colors": [CardEnums.CardColor.BLUE],
		"invasion_icon": 1,
		"description": "Choose 1 of your opponent's zones. <Destroy> all of your opponent's battle cards in that zone and zones adjacent to it.\n(For example, if a card is in zone 7, the adjacent zones are 4, 6, and 8.)",
		"effect_script": "res://scripts/effects/esd02/esd02_015.gd"
	},
]


# --- Deck Building ---

func get_monster_deck(trait_type: CardEnums.CardTrait) -> Array[Dictionary]:
	# Search official set cards for monster deck of given trait
	var monsters: Array[Dictionary] = []
	for id in CARD_TEMPLATES:
		var card = CARD_TEMPLATES[id]
		if card.get("card_type") == CardEnums.CardType.MONSTER and trait_type in card.get("traits", []):
			monsters.append(card.duplicate())
	if monsters.is_empty():
		push_error("CardData: No monster deck for trait %s" % trait_type)
	return monsters


func get_main_deck(deck_id: int) -> Array[Dictionary]:
	return get_esd01_main_deck(deck_id)


func get_esd01_main_deck(deck_id: int) -> Array[Dictionary]:
	## Builds a 50-card main deck from ESD01 (Godzilla Minus One) cards.
	var deck: Array[Dictionary] = []

	# --- Burst Monsters (10 cards, for invasion/rage fuel) ---

	# 4x ESD01-005: Godzilla (2023) Burst I (R2, TL 12000, inv 1)
	for i in range(4):
		var card = CARD_TEMPLATES["ESD01-005"].duplicate()
		card["id"] = "ESD01-005_%d_%d" % [deck_id, i]
		deck.append(card)

	# 3x ESD01-006: Godzilla (2023) Burst II (R3, TL 23000, inv 1)
	for i in range(3):
		var card = CARD_TEMPLATES["ESD01-006"].duplicate()
		card["id"] = "ESD01-006_%d_%d" % [deck_id, i]
		deck.append(card)

	# 3x ESD01-007: Godzilla (2023) Burst III (R4, TL 38000, inv 2)
	for i in range(3):
		var card = CARD_TEMPLATES["ESD01-007"].duplicate()
		card["id"] = "ESD01-007_%d_%d" % [deck_id, i]
		deck.append(card)

	# --- Battle Cards (27 cards) ---

	# 8x ESD01-008: Shinseimaru (R2, CP 2000, inv 1)
	for i in range(8):
		var card = CARD_TEMPLATES["ESD01-008"].duplicate()
		card["id"] = "ESD01-008_%d_%d" % [deck_id, i]
		deck.append(card)

	# 6x ESD01-009: Reinforcements (R4, CP 2000, inv 1)
	for i in range(6):
		var card = CARD_TEMPLATES["ESD01-009"].duplicate()
		card["id"] = "ESD01-009_%d_%d" % [deck_id, i]
		deck.append(card)

	# 3x ESD01-010: City of Tokyo (R6, CP 0, inv 1)
	for i in range(3):
		var card = CARD_TEMPLATES["ESD01-010"].duplicate()
		card["id"] = "ESD01-010_%d_%d" % [deck_id, i]
		deck.append(card)

	# 6x ESD01-011: Godzilla (2023) Battle (R5, CP 3000, inv 1)
	for i in range(6):
		var card = CARD_TEMPLATES["ESD01-011"].duplicate()
		card["id"] = "ESD01-011_%d_%d" % [deck_id, i]
		deck.append(card)

	# 4x ESD01-012: Godzilla (2023) Battle (R7, CP 7000, inv 2)
	for i in range(4):
		var card = CARD_TEMPLATES["ESD01-012"].duplicate()
		card["id"] = "ESD01-012_%d_%d" % [deck_id, i]
		deck.append(card)

	# --- Strategy Cards (13 cards) ---

	# 4x ESD01-013: Ginza Annihilated (R4, inv 1)
	for i in range(4):
		var card = CARD_TEMPLATES["ESD01-013"].duplicate()
		card["id"] = "ESD01-013_%d_%d" % [deck_id, i]
		deck.append(card)

	# 3x ESD01-014: Godzilla Emerges (R6, inv 1)
	for i in range(3):
		var card = CARD_TEMPLATES["ESD01-014"].duplicate()
		card["id"] = "ESD01-014_%d_%d" % [deck_id, i]
		deck.append(card)

	# 3x ESD01-015: Operation Wadatsumi (R7, inv 1)
	for i in range(3):
		var card = CARD_TEMPLATES["ESD01-015"].duplicate()
		card["id"] = "ESD01-015_%d_%d" % [deck_id, i]
		deck.append(card)

	# 3x ESD01-016: Heat Ray (R1, inv 1)
	for i in range(3):
		var card = CARD_TEMPLATES["ESD01-016"].duplicate()
		card["id"] = "ESD01-016_%d_%d" % [deck_id, i]
		deck.append(card)

	# Total: 10 + 27 + 13 = 50 cards
	# Invasion icon 2 count: 3 (ESD01-007) + 4 (ESD01-012) = 7 (under 10 limit)
	return deck


func get_card_by_id(id: String) -> Dictionary:
	if CARD_TEMPLATES.has(id):
		return CARD_TEMPLATES[id]
	return {}
