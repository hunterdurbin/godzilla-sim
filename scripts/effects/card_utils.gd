class_name CardUtils

## Pure static helpers for querying card Dictionary data.
## Stateless — use for trait/color/type checks that otherwise inline
## `card.get("traits", [])` / `card.get("card_type") == ...` patterns.


static func base_id(card: Dictionary) -> String:
	## Strip the per-copy suffix from a card's instance id ("EBP04-067_0_3" →
	## "EBP04-067"). Use this when comparing against card-data ids in effect
	## logic — the raw `card["id"]` is the per-copy instance id at runtime.
	var id: String = card.get("id", "")
	var underscore: int = id.find("_")
	return id if underscore < 0 else id.substr(0, underscore)


static func has_trait(card: Dictionary, trait_id: int) -> bool:
	return trait_id in card.get("traits", [])


static func has_any_trait(card: Dictionary, trait_ids: Array) -> bool:
	var card_traits: Array = card.get("traits", [])
	for t in trait_ids:
		if t in card_traits:
			return true
	return false


static func has_color(card: Dictionary, color: int) -> bool:
	return color in card.get("colors", [])


static func is_type(card: Dictionary, card_type: int) -> bool:
	return card.get("card_type") == card_type


static func is_battle(card: Dictionary) -> bool:
	return card.get("card_type") == CardEnums.CardType.BATTLE


static func is_strategy(card: Dictionary) -> bool:
	return card.get("card_type") == CardEnums.CardType.STRATEGY


static func is_monster(card: Dictionary) -> bool:
	return card.get("card_type") == CardEnums.CardType.MONSTER


static func rank_at_least(card: Dictionary, rank: int) -> bool:
	return card.get("rank", 0) >= rank


static func rank_at_most(card: Dictionary, rank: int) -> bool:
	return card.get("rank", 0) <= rank


# --- Aggregations over card arrays ---

static func count(cards: Array, filter: Callable) -> int:
	## Count cards in `cards` for which `filter(card) -> bool` returns true.
	## Use a composed filter to handle "counts_as_X" semantics, e.g. when
	## counting monster cards in the discard pile EBP03-071 (Godzilla's
	## Skeleton) declares "counts_as_monster_in_discard" and should be
	## included via:
	##   func(c): return CardUtils.is_monster(c) or c.get("counts_as_monster_in_discard", false)
	var n: int = 0
	for card in cards:
		if filter.call(card):
			n += 1
	return n


static func count_monsters_in_discard(discard_pile: Array) -> int:
	## Count monster cards in a discard pile. Includes cards with the
	## "counts_as_monster_in_discard" flag (e.g. EBP03-071 Godzilla's Skeleton).
	return count(discard_pile,
		func(c: Dictionary) -> bool:
			return is_monster(c) or c.get("counts_as_monster_in_discard", false))


static func count_distinct_colors(cards: Array, filter: Callable = Callable()) -> int:
	## Count distinct colors across cards matching `filter`. When `filter` is
	## an empty Callable (default), every card is considered. Used by effects
	## like EBP04-032 (threat = colors × 10000) and EBP04-068 (strategy rank
	## reduction = -colors among battle cards in discard).
	var colors: Array[int] = []
	for card in cards:
		if filter.is_valid() and not filter.call(card):
			continue
		for c: int in card.get("colors", []):
			if c not in colors:
				colors.append(c)
	return colors.size()
