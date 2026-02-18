class_name DeckValidator
## Static deck validation utilities shared by DecklistManager and DeckBuilder.

# --- Error messages ---
const ERR_UNKNOWN_CARD := "Unknown card: %s"
const ERR_NOT_MONSTER := "%s is not a monster card"
const ERR_TOKEN_IN_DECK := "%s has Token trait (not allowed in decks)"
const ERR_DUPLICATE_RANK := "Duplicate monster rank %d"
const ERR_MONSTER_COUNT := "Monster deck must have exactly 4 cards (has %d)"
const ERR_MISSING_RANK := "Monster deck missing rank %d"
const ERR_COLOR_MISMATCH := "%s [%s] color doesn't match monster deck"
const ERR_MAIN_COUNT := "Main deck must have exactly 50 cards (has %d)"
const ERR_STEP2_LIMIT := "Main deck has %d Step-2 cards (max 10)"
const ERR_COPY_LIMIT := "Card %s has %d copies (max 4)"
const ERR_MISSING_TRAIT := "%s [%s] missing required trait (%s)"
const ERR_BELOW_MIN_RANK := "%s [%s] rank %d is below minimum %d"
const ERR_STRATEGY_COUNT := "Deck needs at least %d strategy cards (has %d)"

# --- Warning messages ---
const WARN_NO_SHARED_TRAITS := "%s (rank %d) shares no traits with %s (rank %d)"


static func validate(monster_entries: Array, main_entries: Array) -> Array[String]:
	## Returns an array of error strings. Empty array = valid deck.
	var errors: Array[String] = []
	var card_number_counts: Dictionary = {} # base card_number -> total count

	# --- Monster Deck ---
	var monster_total := 0
	var monster_ranks_found: Dictionary = {} # rank -> true
	var allowed_colors: Array[int] = [CardEnums.CardColor.WHITE]
	var resonance: Dictionary = {}

	for entry in monster_entries:
		var cn: String = entry["card_number"]
		var base_cn: String = cn.trim_suffix("+")
		var qty: int = entry["quantity"]
		monster_total += qty
		card_number_counts[base_cn] = card_number_counts.get(base_cn, 0) + qty

		var template: Dictionary = CardData.CARD_TEMPLATES.get(cn, {})
		if template.is_empty():
			errors.append(ERR_UNKNOWN_CARD % cn)
			continue

		if template.get("card_type") != CardEnums.CardType.MONSTER:
			errors.append(ERR_NOT_MONSTER % cn)
			continue

		if CardEnums.CardTrait.TOKEN in template.get("traits", []):
			errors.append(ERR_TOKEN_IN_DECK % cn)

		var rank: int = template.get("rank", 0)
		for _i in range(qty):
			if rank in monster_ranks_found:
				errors.append(ERR_DUPLICATE_RANK % rank)
			else:
				monster_ranks_found[rank] = true

		if rank == 1:
			for c: int in template.get("colors", []):
				if c not in allowed_colors:
					allowed_colors.append(c)
			resonance = template.get("resonance", {})

	if monster_total != 4:
		errors.append(ERR_MONSTER_COUNT % monster_total)

	for r in [1, 2, 3, 4]:
		if r not in monster_ranks_found:
			errors.append(ERR_MISSING_RANK % r)

	# Color check for monster deck cards (second pass)
	if allowed_colors.size() > 1:
		for entry in monster_entries:
			var template: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
			if template.is_empty():
				continue
			if not _has_allowed_color(template, allowed_colors):
				errors.append(ERR_COLOR_MISMATCH % [
					template.get("name", entry["card_number"]), entry["card_number"]])

	# --- Main Deck ---
	var main_total := 0
	var invasion2_count := 0

	for entry in main_entries:
		var cn: String = entry["card_number"]
		var base_cn: String = cn.trim_suffix("+")
		var qty: int = entry["quantity"]
		main_total += qty
		card_number_counts[base_cn] = card_number_counts.get(base_cn, 0) + qty

		var template: Dictionary = CardData.CARD_TEMPLATES.get(cn, {})
		if template.is_empty():
			errors.append(ERR_UNKNOWN_CARD % cn)
			continue

		if CardEnums.CardTrait.TOKEN in template.get("traits", []):
			errors.append(ERR_TOKEN_IN_DECK % cn)

		if template.get("invasion_icon", 0) >= 2:
			invasion2_count += qty

		# Color check
		if allowed_colors.size() > 1:
			if not _has_allowed_color(template, allowed_colors):
				errors.append(ERR_COLOR_MISMATCH % [template.get("name", cn), cn])

	if main_total != 50:
		errors.append(ERR_MAIN_COUNT % main_total)

	if invasion2_count > 10:
		errors.append(ERR_STEP2_LIMIT % invasion2_count)

	# --- Cross-deck copy limit ---
	for cn in card_number_counts:
		if card_number_counts[cn] > 4:
			var tmpl: Dictionary = CardData.CARD_TEMPLATES.get(cn, {})
			if not tmpl.get("unlimited_copies", false):
				errors.append(ERR_COPY_LIMIT % [cn, card_number_counts[cn]])

	# --- Resonance requirements ---
	if not resonance.is_empty():
		errors.append_array(_validate_resonance(resonance, main_entries))

	return errors


static func get_invalid_cards(monster_entries: Array, main_entries: Array) -> Dictionary:
	## Returns a Dictionary of card_number -> true for cards with per-card errors.
	var invalid: Dictionary = {}

	# Derive allowed colors and resonance from rank 1 monster
	var allowed_colors: Array[int] = [CardEnums.CardColor.WHITE]
	var resonance: Dictionary = {}
	for entry in monster_entries:
		var tmpl: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		if tmpl.get("rank", 0) == 1:
			for c: int in tmpl.get("colors", []):
				if c not in allowed_colors:
					allowed_colors.append(c)
			resonance = tmpl.get("resonance", {})
			break

	# Copy counts for limit check
	var card_number_counts: Dictionary = {}
	for entry in monster_entries:
		var base: String = entry["card_number"].trim_suffix("+")
		card_number_counts[base] = card_number_counts.get(base, 0) + entry["quantity"]
	for entry in main_entries:
		var base: String = entry["card_number"].trim_suffix("+")
		card_number_counts[base] = card_number_counts.get(base, 0) + entry["quantity"]

	# Monster deck checks
	for entry in monster_entries:
		var cn: String = entry["card_number"]
		var tmpl: Dictionary = CardData.CARD_TEMPLATES.get(cn, {})
		if tmpl.is_empty():
			invalid[cn] = true
			continue
		if tmpl.get("card_type") != CardEnums.CardType.MONSTER:
			invalid[cn] = true
		if CardEnums.CardTrait.TOKEN in tmpl.get("traits", []):
			invalid[cn] = true
		if allowed_colors.size() > 1 and not _has_allowed_color(tmpl, allowed_colors):
			invalid[cn] = true
		var base: String = cn.trim_suffix("+")
		if card_number_counts.get(base, 0) > 4 and not tmpl.get("unlimited_copies", false):
			invalid[cn] = true

	# Main deck checks
	var req_monster_traits: Array = resonance.get("main_monster_required_traits", [])
	var req_battle_traits: Array = resonance.get("main_battle_required_traits", [])
	var min_battle_rank: int = resonance.get("main_battle_min_rank", 0)

	for entry in main_entries:
		var cn: String = entry["card_number"]
		var tmpl: Dictionary = CardData.CARD_TEMPLATES.get(cn, {})
		if tmpl.is_empty():
			invalid[cn] = true
			continue
		if CardEnums.CardTrait.TOKEN in tmpl.get("traits", []):
			invalid[cn] = true
		if allowed_colors.size() > 1 and not _has_allowed_color(tmpl, allowed_colors):
			invalid[cn] = true
		var base: String = cn.trim_suffix("+")
		if card_number_counts.get(base, 0) > 4 and not tmpl.get("unlimited_copies", false):
			invalid[cn] = true
		var card_type: int = tmpl.get("card_type", -1)
		var traits: Array = tmpl.get("traits", [])
		if card_type == CardEnums.CardType.MONSTER and not req_monster_traits.is_empty():
			if not _has_any_trait(traits, req_monster_traits):
				invalid[cn] = true
		if card_type == CardEnums.CardType.BATTLE and not req_battle_traits.is_empty():
			if not _has_any_trait(traits, req_battle_traits):
				invalid[cn] = true
		if card_type == CardEnums.CardType.BATTLE and min_battle_rank > 0:
			if tmpl.get("rank", 0) < min_battle_rank:
				invalid[cn] = true

	return invalid


static func warnings(monster_entries: Array, main_entries: Array) -> Array[String]:
	## Returns an array of warning strings (e.g. no valid rank-up path).
	@warning_ignore("unused_parameter")
	var _unused := main_entries # main_entries reserved for future warning checks
	var result: Array[String] = []

	var rank_cards: Dictionary = {}
	for entry in monster_entries:
		var template: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		if template.is_empty():
			continue
		rank_cards[template.get("rank", 0)] = template

	for r in [1, 2, 3]:
		if r not in rank_cards or (r + 1) not in rank_cards:
			continue
		var current: Dictionary = rank_cards[r]
		var next: Dictionary = rank_cards[r + 1]
		var current_traits: Array = current.get("traits", [])
		var next_traits: Array = next.get("traits", [])
		var shared := false
		for t in current_traits:
			if t in next_traits:
				shared = true
				break
		if not shared:
			result.append(WARN_NO_SHARED_TRAITS % [
				current.get("name", "Rank %d" % r), r,
				next.get("name", "Rank %d" % (r + 1)), r + 1])

	return result


# --- Internal helpers ---

static func _has_allowed_color(template: Dictionary, allowed_colors: Array[int]) -> bool:
	for c in template.get("colors", []):
		if c in allowed_colors:
			return true
	return false


static func _has_any_trait(card_traits: Array, required_traits: Array) -> bool:
	for t in required_traits:
		if t in card_traits:
			return true
	return false


static func _trait_names_string(traits: Array) -> String:
	var names: Array[String] = []
	for t in traits:
		names.append(CardEnums.trait_to_string(t))
	return " or ".join(names)


static func _validate_resonance(resonance: Dictionary, main_entries: Array) -> Array[String]:
	var errors: Array[String] = []
	var req_monster_traits: Array = resonance.get("main_monster_required_traits", [])
	var req_battle_traits: Array = resonance.get("main_battle_required_traits", [])
	var min_battle_rank: int = resonance.get("main_battle_min_rank", 0)
	var min_strategy_count: int = resonance.get("main_strategy_min_count", 0)

	var strategy_count := 0
	for entry in main_entries:
		var tmpl: Dictionary = CardData.CARD_TEMPLATES.get(entry["card_number"], {})
		if tmpl.is_empty():
			continue
		var card_type: int = tmpl.get("card_type", -1)
		var traits: Array = tmpl.get("traits", [])
		var card_label: Array = [tmpl.get("name", entry["card_number"]), entry["card_number"]]

		if card_type == CardEnums.CardType.STRATEGY:
			strategy_count += entry["quantity"]

		if card_type == CardEnums.CardType.MONSTER and not req_monster_traits.is_empty():
			if not _has_any_trait(traits, req_monster_traits):
				errors.append(ERR_MISSING_TRAIT % [card_label[0], card_label[1],
					_trait_names_string(req_monster_traits)])

		if card_type == CardEnums.CardType.BATTLE and not req_battle_traits.is_empty():
			if not _has_any_trait(traits, req_battle_traits):
				errors.append(ERR_MISSING_TRAIT % [card_label[0], card_label[1],
					_trait_names_string(req_battle_traits)])

		if card_type == CardEnums.CardType.BATTLE and min_battle_rank > 0:
			if tmpl.get("rank", 0) < min_battle_rank:
				errors.append(ERR_BELOW_MIN_RANK % [card_label[0], card_label[1],
					tmpl.get("rank", 0), min_battle_rank])

	if min_strategy_count > 0 and strategy_count < min_strategy_count:
		errors.append(ERR_STRATEGY_COUNT % [min_strategy_count, strategy_count])

	return errors
