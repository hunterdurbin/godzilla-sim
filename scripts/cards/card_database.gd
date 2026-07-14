extends Node
## Autoload singleton "CardData": the card template database.
## Per-set card definitions live in sets/card_set_*.gd (data only);
## this file owns indexing, printing overrides, and deck builders.

const _SET_SCRIPTS: Array = [
	preload("sets/card_set_ebp01.gd"),
	preload("sets/card_set_ebp02.gd"),
	preload("sets/card_set_ebp03.gd"),
	preload("sets/card_set_ebp04.gd"),
	preload("sets/card_set_epr.gd"),
	preload("sets/card_set_esd01.gd"),
	preload("sets/card_set_esd02.gd"),
	preload("sets/card_set_esc01.gd"),
	preload("sets/card_set_efc01.gd"),
	preload("sets/card_set_system.gd"),
]



# Card template registry - maps card numbers to their base data (no copy-specific IDs)
var CARD_TEMPLATES: Dictionary = {}


func _ready() -> void:
	_build_card_templates()


func _build_card_templates() -> void:
	# Index all cards by their ID (set data lives in sets/card_set_*.gd)
	for card_set in _SET_SCRIPTS:
		for card in card_set.new().CARDS:
			CARD_TEMPLATES[card["id"]] = card.duplicate()


# --- Per-printing card overrides ---
# A card may declare optional `<field>_by_printing` maps (e.g. `traits_by_printing`)
# holding alternate values per printing. The English release ("en") is the canonical
# base value; some formats swap in an alternate (currently only Rumble East → "ja",
# which corrects the EBP02-015 trait misprint). Overrides are resolved per-match in
# TurnManager.setup() — NOT baked into CARD_TEMPLATES — because the active format can
# change between games without restarting.

## Maps a game mode id to the card printing it uses. Rumble East uses the Japanese
## printing; every other format (and private/LAN "") uses English.
func printing_for_mode(game_mode: String) -> String:
	return "ja" if GameModeValidator.normalize_mode_id(game_mode) == "rumble_east" else "en"


## Read-only: returns `card`'s value for `field` under `printing`, falling back to the
## base field (or `default` when the base field is absent too). Does not mutate the card.
## Safe to call on shared templates (e.g. from the deck builder / validators).
func get_printed_field(card: Dictionary, field: String, printing: String, default: Variant = null) -> Variant:
	var overrides: Dictionary = card.get(field + "_by_printing", {})
	if overrides.has(printing):
		return overrides[printing]
	return card.get(field, default)


## Mutates `card` in place: applies every `<field>_by_printing` override for the given
## printing onto its base field, then strips the helper keys so they never leak to
## consumers or serialization. Call only on per-match instances, never on a template.
func apply_printing(card: Dictionary, printing: String) -> void:
	for key in card.keys(): # keys() returns a snapshot, so erasing during iteration is safe
		if not (key is String and key.ends_with("_by_printing")):
			continue
		var overrides: Dictionary = card[key]
		if overrides.has(printing):
			var value: Variant = overrides[printing]
			card[key.trim_suffix("_by_printing")] = value.duplicate() if value is Array or value is Dictionary else value
		card.erase(key)


# --- SYSTEM: Engine-internal placeholder cards (not from any set) ---
# These represent in-game concepts (e.g. <Rage>) as physical cards so they can
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
