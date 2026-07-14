class_name DeckBuilderPadHints
extends RefCounted

## Pure controller-hint and section-cycle logic for the deck builder, kept
## static so gdUnit covers it headlessly (same pattern as HandHintBar's
## compute_hint_actions core).

## LB/RB cycle order over the major screen areas.
const SECTIONS: Array[String] = ["left", "deck", "pool"]


## ctx: {"area": "deck"|"pool"|"text"|"chrome", "monster_tab": bool,
## "is_monster_type": bool, "in_monster": bool} — area is "deck"/"pool" only
## while a card wrapper holds focus, "text" while a text box holds it;
## everything else is "chrome".
## Returns [{action, text_key, action2?}]; the caller tr()s text_key into the
## pre-translated "text" OverlayHintRow.set_hints expects.
static func compute(ctx: Dictionary) -> Array[Dictionary]:
	var hints: Array[Dictionary] = []
	match String(ctx.get("area", "chrome")):
		"pool":
			hints.append({"action": &"pad_confirm", "text_key": "STR_DB_HINT_ADD"})
			hints.append({"action": &"pad_end_main", "text_key": "STR_DB_HINT_REMOVE"})
		"deck":
			hints.append({"action": &"pad_confirm", "text_key": "STR_DB_HINT_REMOVE"})
			hints.append({"action": &"pad_end_main", "text_key": _deck_secondary_key(ctx)})
		"text":
			hints.append({"action": &"pad_confirm", "text_key": "STR_DB_HINT_TYPE"})
		_:
			hints.append({"action": &"pad_confirm", "text_key": "STR_GB_HINT_SELECT"})
	hints.append({"action": &"pad_focus_log", "action2": &"pad_focus_tracker",
			"text_key": "STR_DB_HINT_SECTION"})
	hints.append({"action": &"pad_cancel", "text_key": "STR_DB_HINT_BACK"})
	return hints


## X on a deck card mirrors the pointer affordances: the hover move button on
## monster-type cards (To Main on the monster tab or when the monster deck
## holds this card; To Monster otherwise) and right-click remove-all on
## everything else.
static func _deck_secondary_key(ctx: Dictionary) -> String:
	if ctx.get("monster_tab", false):
		return "STR_DB_HINT_TO_MAIN"
	if ctx.get("is_monster_type", false):
		if ctx.get("in_monster", false):
			return "STR_DB_HINT_TO_MAIN"
		return "STR_DB_HINT_TO_MONSTER"
	return "STR_DB_HINT_REMOVE_ALL"


static func next_section(current: String, dir: int) -> String:
	var idx := maxi(SECTIONS.find(current), 0)
	return SECTIONS[(idx + dir + SECTIONS.size()) % SECTIONS.size()]
