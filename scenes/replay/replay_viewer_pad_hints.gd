class_name ReplayViewerPadHints
extends RefCounted

## Pure controller-hint logic for the replay viewer, kept static so gdUnit
## covers it headlessly (same pattern as DeckBuilderPadHints).


## ctx: {"overlay": "zoom"|"gallery"|"", "area": "card"|"slider"|"chrome"} —
## an open overlay wins over the focus area (the hint row floats above both
## overlays, so it must describe the topmost surface).
## Returns [{action, text_key, action2?}]; the caller tr()s text_key into the
## pre-translated "text" OverlayHintRow.set_hints expects.
static func compute(ctx: Dictionary) -> Array[Dictionary]:
	match String(ctx.get("overlay", "")):
		"zoom":
			return [{"action": &"pad_cancel", "text_key": "STR_GB_HINT_CLOSE"}]
		"gallery":
			return [
				{"action": &"pad_inspect", "text_key": "STR_GB_HINT_INSPECT"},
				{"action": &"pad_cancel", "text_key": "STR_GB_HINT_CLOSE"},
			]
	var hints: Array[Dictionary] = []
	match String(ctx.get("area", "chrome")):
		"card":
			hints.append({"action": &"pad_inspect", "text_key": "STR_GB_HINT_INSPECT"})
		"slider":
			hints.append({"action": &"pad_nav_left", "action2": &"pad_nav_right",
					"text_key": "STR_RV_HINT_ADJUST"})
		_:
			hints.append({"action": &"pad_confirm", "text_key": "STR_GB_HINT_SELECT"})
	# Bumpers step one snapshot, triggers jump a whole turn — always live.
	hints.append({"action": &"pad_focus_log", "action2": &"pad_focus_tracker",
			"text_key": "STR_RV_HINT_STEP"})
	hints.append({"action": &"pad_play_card_rage", "action2": &"pad_play_card_invasion",
			"text_key": "STR_RV_HINT_TURN"})
	hints.append({"action": &"pad_cancel", "text_key": "STR_RV_EXIT"})
	return hints
