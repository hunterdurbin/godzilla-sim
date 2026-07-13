@tool
class_name BoardNavGraph
extends RefCounted
## Builds the ONE directional navigation graph for the controller cursor:
## playmat elements, hand cards, action-panel buttons, hand-button stacks,
## system buttons, the log/chat panel, turn-tracker labels and choice-prompt
## buttons are all nodes in the same up/right/down/left adjacency dictionary
## (resolved by CursorMap). GamepadBoardNav rebuilds it lazily whenever the
## dynamic parts change (hand size, choice prompt, layout).
##
## EDIT THE TABLES BELOW to change where the cursor travels. Each element
## lists its up/right/down/left targets; multiple candidates in one direction
## are tie-broken by the last-10-visited history ("return where you came
## from"), then list order. Invalid/hidden elements are traversed THROUGH
## transparently, so a hidden button never blocks a lane.
##
## Three sentinels may appear in edge lists and are expanded by build().
## The fan sentinels mark GEOMETRIC slots, not id families:
##   "hand"     -> the fan BELOW the bottom row: the card nearest (center X)
##                 to the source element, or ap_sort_hand when empty
##   "opp_hand" -> the fan ABOVE the top row: the nearest card; dropped with
##                 no fallback when that fan is empty
##   "tracker"  -> every trk_<i> label (history picks where you left off)
## Which id family (hand_<i> / opp_hand_<i>) fills each slot follows the
## `hand_at_top` ctx flag — hand_<i> is always the ACTING hand, and in a
## hotseat P2 turn that fan physically sits at the top.
##
## DORMANT: the ctx key `zone_jail_side` can seal a playmat's z1-z8 into
## the ZONE_JAIL_EDGES table (wrap-around rows without the rage/hand/deck
## exits). The live board always passes "" — zone prompts free-roam now
## (GamepadBoardNav._zone_jail_side); kept for the graph tests and possible
## reuse.
##
## Element ids are VISUAL (seat-independent): `bot_*` = the bottom playmat,
## `top_*` = the opponent playmat at the top. Dynamic ids: hand_<i> (the
## ACTING hand's fanned cards, left to right), opp_hand_<i> (the other
## seat's fan — roam/zoom only, plays stay gated to hand_<i>; each row is
## wired to whichever board edge its fan PHYSICALLY sits on, see
## hand_at_top), trk_<i> (turn-tracker labels, top to bottom),
## choice_<i> (choice-prompt buttons, top to bottom), stack_<i>
## (pending-effect rows, top to bottom — chained to choice_0 when a choice
## is open, otherwise entered via the Select toggle or from the top board),
## hint_<i> (prompt-preview mini cards above the action prompt, left to
## right — only mapped while a prompt shows them).
## Button ids: ap_* = action panel + hand stacks + mobile FAB, sys_* = the
## corner utility column, log_panel = the game log/chat panel.
##
## @tool-safe and scene-free: build() is a pure function of the ctx
## Dictionary, so unit tests and the editor overlay feed it fake data.

const HAND_SENTINEL := "hand"
const OPP_HAND_SENTINEL := "opp_hand"
const TRACKER_SENTINEL := "tracker"

## Exits used for `up` from every hand card (history returns the cursor to
## wherever it entered the hand from).
const HAND_EXITS: Array[String] = [
	"bot_z2", "bot_z3", "bot_z1", "bot_z4", "bot_z5",
	"bot_monster_deck", "bot_discard",
]

## Exits used for `down` from every opponent hand card — mirror of
## HAND_EXITS on the top playmat.
const OPP_HAND_EXITS: Array[String] = [
	"top_z2", "top_z3", "top_z1", "top_z4", "top_z5",
	"top_monster_deck", "top_discard",
]

## The playmat table — a direct transcription of the annotated layout:
##
##   top r1:  discard | z5 | z4 | z3 | z2 | z1 | monster_deck
##   top r2:  deck    | z6 | z7 | z8 | rage | strategy(1 over 0)
##   bot r1:  strategy(0 over 1) | rage | z8 | z7 | z6 | deck
##   bot r2:  monster_deck | z1 | z2 | z3 | z4 | z5 | discard
##   hand:    below bot r2
##
## Seams to the surrounding UI (log panel on the left, tracker/sys column on
## the right) are part of each element's lists here — there is no separate
## border table to cross-reference.
const PLAYMAT := {
	# --- Top board, row 1 (screen top) ---
	"top_discard": {"up": ["sys_save", "opp_hand"], "right": ["top_z5"], "down": ["top_deck"], "left": ["sys_save", "log_panel"]},
	"top_z5": {"up": ["opp_hand"], "right": ["top_z4"], "down": ["top_z6"], "left": ["top_discard"]},
	"top_z4": {"up": ["opp_hand"], "right": ["top_z3"], "down": ["top_z7"], "left": ["top_z5"]},
	"top_z3": {"up": ["opp_hand"], "right": ["top_z2"], "down": ["top_z8"], "left": ["top_z4"]},
	"top_z2": {"up": ["opp_hand"], "right": ["top_z1"], "down": ["top_rage"], "left": ["top_z3"]},
	"top_z1": {"up": ["opp_hand"], "right": ["top_monster_deck"], "down": ["top_strategy_1"], "left": ["top_z2"]},
	"top_monster_deck": {"up": ["opp_hand"], "right": ["ap_opp_hand_toggle", "sys_bug_report"], "down": ["top_strategy_0", "top_strategy_1"], "left": ["top_z1"]},

	# --- Top board, row 2 (nearer the divider) ---
	# Divider seams pair TRUE screen columns: the top playmat is offset one
	# column right of the bottom one, so top_z6 sits over the strategy
	# column, top_z7 over rage, top_z8 over bot_z8, rage over bot_z7 and the
	# strategy column over bot_z6.
	"top_deck": {"up": ["top_discard"], "right": ["top_z6"], "down": ["bot_strategy_0"], "left": ["log_panel"]},
	"top_z6": {"up": ["top_z5"], "right": ["top_z7"], "down": ["bot_strategy_0"], "left": ["top_deck"]},
	"top_z7": {"up": ["top_z4"], "right": ["top_z8"], "down": ["bot_rage"], "left": ["top_z6"]},
	"top_z8": {"up": ["top_z3"], "right": ["top_rage"], "down": ["bot_z8"], "left": ["top_z7"]},
	"top_rage": {"up": ["top_z2"], "right": ["top_strategy_1"], "down": ["bot_z7"], "left": ["top_z8"]},
	# Mirrored strategy column: strategy_1 sits ABOVE strategy_0 on the top board.
	"top_strategy_1": {"up": ["top_z1", "top_monster_deck"], "right": ["tracker", "sys_export_log"], "down": ["top_strategy_0"], "left": ["top_rage"]},
	"top_strategy_0": {"up": ["top_strategy_1"], "right": ["tracker"], "down": ["bot_z6"], "left": ["top_rage"]},
	"top_strategy_2": {"up": ["top_strategy_0"], "right": ["tracker"], "down": ["bot_z6"], "left": ["top_rage"]},

	# --- Bottom board, row 1 (nearer the divider) ---
	"bot_strategy_0": {"up": ["top_z6", "top_deck"], "right": ["bot_rage"], "down": ["bot_strategy_1"], "left": ["log_panel"]},
	"bot_strategy_1": {"up": ["bot_strategy_0"], "right": ["bot_rage"], "down": ["bot_monster_deck", "bot_z1"], "left": ["log_panel"]},
	"bot_strategy_2": {"up": ["bot_strategy_1"], "right": ["bot_rage"], "down": ["bot_monster_deck", "bot_z1"], "left": ["log_panel"]},
	"bot_rage": {"up": ["top_z7"], "right": ["bot_z8"], "down": ["bot_z1", "bot_z2"], "left": ["bot_strategy_0"]},
	"bot_z8": {"up": ["top_z8"], "right": ["bot_z7"], "down": ["bot_z3"], "left": ["bot_rage"]},
	"bot_z7": {"up": ["top_rage"], "right": ["bot_z6"], "down": ["bot_z4"], "left": ["bot_z8"]},
	"bot_z6": {"up": ["top_strategy_0"], "right": ["bot_deck"], "down": ["bot_z5"], "left": ["bot_z7"]},
	"bot_deck": {"up": ["top_strategy_0"], "right": ["tracker"], "down": ["bot_discard"], "left": ["bot_z6"]},

	# --- Bottom board, row 2 ---
	"bot_monster_deck": {"up": ["bot_strategy_1"], "right": ["bot_z1"], "down": ["hand"], "left": []},
	"bot_z1": {"up": ["bot_rage"], "right": ["bot_z2"], "down": ["hand"], "left": ["bot_monster_deck"]},
	"bot_z2": {"up": ["bot_rage"], "right": ["bot_z3"], "down": ["hand"], "left": ["bot_z1"]},
	"bot_z3": {"up": ["bot_z8"], "right": ["bot_z4"], "down": ["hand"], "left": ["bot_z2"]},
	"bot_z4": {"up": ["bot_z7"], "right": ["bot_z5"], "down": ["hand"], "left": ["bot_z3"]},
	"bot_z5": {"up": ["bot_z6"], "right": ["bot_discard"], "down": ["hand"], "left": ["bot_z4"]},
	"bot_discard": {"up": ["bot_deck"], "right": ["tracker"], "down": ["hand"], "left": ["bot_z5"]},
}

## DORMANT (live board always passes zone_jail_side "" — see
## GamepadBoardNav._zone_jail_side; kept for graph tests / possible reuse).
## Zone-only edges swapped in while `zone_jail_side` seals a playmat:
## both zone rows chain with wrap-around at the ends
## (z5<->z1, z6<->z8), and up/down always reach the paired zone in the other
## row (z3<->z8, z4<->z7, z5<->z6) — z1/z2 route up/down to z8 one-way, z8
## only ever returns to z3. The cursor never dead-ends in any direction, so
## every zone stays reachable even though the jail cuts the rage/hand/deck
## exits. Authored for the bottom playmat; the top playmat (mirrored on both
## axes) gets the directions flipped.
const ZONE_JAIL_EDGES := {
	1: {"up": ["z8"], "right": ["z2"], "down": ["z8"], "left": ["z5"]},
	2: {"up": ["z8"], "right": ["z3"], "down": ["z8"], "left": ["z1"]},
	3: {"up": ["z8"], "right": ["z4"], "down": ["z8"], "left": ["z2"]},
	4: {"up": ["z7"], "right": ["z5"], "down": ["z7"], "left": ["z3"]},
	5: {"up": ["z6"], "right": ["z1"], "down": ["z6"], "left": ["z4"]},
	6: {"up": ["z5"], "right": ["z8"], "down": ["z5"], "left": ["z7"]},
	7: {"up": ["z4"], "right": ["z6"], "down": ["z4"], "left": ["z8"]},
	8: {"up": ["z3"], "right": ["z7"], "down": ["z3"], "left": ["z6"]},
}

const _FLIP := {"up": "down", "right": "left", "down": "up", "left": "right"}

## Desktop action panel (bottom-right 3-row grid), hand-button stacks and the
## corner utility column. Rows: Cancel|Confirm / Battle|Strategy|Rage /
## Monster|Invade|EndMain; the hand toggle/sort pair is a vertical column
## (toggle above sort) immediately left of the panel — toggle level with the
## Battle row, sort level with the Monster row.
const DESKTOP_UI := {
	"ap_cancel": {"up": ["tracker"], "right": ["ap_confirm"], "down": ["ap_play_battle", "ap_play_strategy"], "left": ["bot_discard"]},
	"ap_confirm": {"up": ["tracker"], "right": [], "down": ["ap_gain_rage", "ap_play_strategy"], "left": ["ap_cancel"]},
	"ap_play_battle": {"up": ["ap_cancel"], "right": ["ap_play_strategy"], "down": ["ap_play_monster"], "left": ["ap_hand_toggle", "bot_discard"]},
	"ap_play_strategy": {"up": ["ap_cancel", "ap_confirm"], "right": ["ap_gain_rage"], "down": ["ap_invade"], "left": ["ap_play_battle"]},
	"ap_gain_rage": {"up": ["ap_confirm"], "right": [], "down": ["ap_end_main"], "left": ["ap_play_strategy"]},
	"ap_play_monster": {"up": ["ap_play_battle"], "right": ["ap_invade"], "down": ["hand"], "left": ["ap_sort_hand", "hand"]},
	"ap_invade": {"up": ["ap_play_strategy"], "right": ["ap_end_main"], "down": ["hand"], "left": ["ap_play_monster"]},
	"ap_end_main": {"up": ["ap_gain_rage"], "right": [], "down": ["hand"], "left": ["ap_invade"]},
	# Hand-button stack (reparented into a VERTICAL column on desktop): toggle
	# sits directly above sort, immediately left of the action panel — toggle
	# level with row1 (Play Battle), sort level with row2 (Play Monster).
	"ap_hand_toggle": {"up": ["ap_cancel"], "right": ["ap_play_battle"], "down": ["ap_sort_hand"], "left": ["hand"]},
	"ap_sort_hand": {"up": ["ap_hand_toggle"], "right": ["ap_play_monster"], "down": [], "left": ["hand"]},

	# Opponent hand stack (hotseat/bot only; hidden -> traversed through).
	# Also a vertical column, top-right: toggle above sort.
	"ap_opp_hand_toggle": {"up": ["opp_hand"], "right": ["sys_bug_report"], "down": ["ap_opp_sort_hand"], "left": ["top_monster_deck"]},
	"ap_opp_sort_hand": {"up": ["ap_opp_hand_toggle"], "right": ["sys_bug_report"], "down": ["top_strategy_1"], "left": ["top_monster_deck"]},

	# Corner utility column (top-right edge, top to bottom).
	"sys_bug_report": {"up": [], "right": [], "down": ["sys_concede"], "left": ["ap_opp_sort_hand", "top_monster_deck"]},
	"sys_concede": {"up": ["sys_bug_report"], "right": [], "down": ["sys_main_menu"], "left": ["top_monster_deck"]},
	"sys_main_menu": {"up": ["sys_concede"], "right": [], "down": ["sys_sound"], "left": ["top_monster_deck"]},
	"sys_sound": {"up": ["sys_main_menu"], "right": [], "down": ["sys_music"], "left": ["top_strategy_1"]},
	"sys_music": {"up": ["sys_sound"], "right": [], "down": ["sys_export_log"], "left": ["top_strategy_1"]},
	"sys_export_log": {"up": ["sys_music"], "right": [], "down": ["tracker"], "left": ["top_strategy_1"]},

	# Save-game button (solo/bot only; created at runtime top-LEFT, above the
	# log panel — absent in multiplayer, so it is traversed through). Live
	# routes in are up/left from top_discard: on the log itself the dpad
	# scrolls the text, so log_panel.up is spatial truth but never walked.
	"sys_save": {"up": [], "right": ["top_discard"], "down": ["log_panel"], "left": []},

	# Game log / chat panel (left edge, vertically centered).
	"log_panel": {"up": ["sys_save"], "right": ["top_deck", "bot_strategy_0", "bot_strategy_1", "top_discard"], "down": [], "left": []},
}

## Mobile UI: FAB grid (row 0 Battle|Monster|Strategy, row 1 Rage|Invade,
## main FAB below) plus the standalone pills next to it, and the hand-button
## stacks. The log tray and tracker tray are NOT stitched into the spatial
## graph on mobile — only the bumpers reach them (the trays slide in).
const MOBILE_UI := {
	"ap_play_battle": {"up": [], "right": ["ap_play_monster"], "down": ["ap_gain_rage"], "left": []},
	"ap_play_monster": {"up": [], "right": ["ap_play_strategy"], "down": ["ap_gain_rage", "ap_invade"], "left": ["ap_play_battle"]},
	"ap_play_strategy": {"up": [], "right": [], "down": ["ap_invade"], "left": ["ap_play_monster"]},
	"ap_gain_rage": {"up": ["ap_play_battle", "ap_play_monster"], "right": ["ap_invade"], "down": ["ap_fab_main"], "left": []},
	"ap_invade": {"up": ["ap_play_monster", "ap_play_strategy"], "right": [], "down": ["ap_fab_main"], "left": ["ap_gain_rage"]},
	"ap_fab_main": {"up": ["ap_invade", "ap_gain_rage"], "right": [], "down": [], "left": ["ap_end_main"]},
	"ap_end_main": {"up": ["hand"], "right": ["ap_fab_main"], "down": [], "left": ["ap_confirm"]},
	"ap_confirm": {"up": ["hand"], "right": ["ap_end_main"], "down": [], "left": ["ap_cancel"]},
	"ap_cancel": {"up": ["hand"], "right": ["ap_confirm"], "down": [], "left": ["ap_sort_hand"]},
	"ap_hand_toggle": {"up": ["hand"], "right": ["ap_sort_hand"], "down": [], "left": []},
	"ap_sort_hand": {"up": ["hand"], "right": ["ap_cancel"], "down": [], "left": ["ap_hand_toggle"]},
	"log_panel": {"up": [], "right": [], "down": [], "left": []},
}

## Build the full adjacency map for CursorMap.
##
## ctx keys (all optional, defaults in parentheses):
##   mobile: bool (false)         — UI edge set to merge
##   hand_count: int (0)          — fanned cards in the acting hand
##   opp_hand_count: int (0)      — fanned cards in the other seat's hand
##   hand_at_top: bool (false)    — the acting hand's fan physically sits
##                                  above the TOP playmat (hotseat P2 turn,
##                                  or a prompt repointing hand_pid at the
##                                  top seat): the hand_<i> row takes the
##                                  top slot and opp_hand_<i> the bottom one
##   tracker_count: int (0)       — interactive turn-tracker labels
##   choice_count: int (0)        — visible choice-prompt buttons
##   stack_count: int (0)         — visible pending-effect rows
##   hint_count: int (0)          — prompt-preview mini cards (effect source /
##                                  placed card / sticky pending-effect slot)
##   zone_jail_side: String ("")  — "bot"/"top" seals that playmat's z1-z8
##                                  with the ZONE_JAIL_EDGES wrap-around
##                                  edges instead of their free-browse rows
##                                  (dormant — the live board always passes
##                                  ""; graph tests still exercise it)
##   rect_of: Callable (invalid)  — id -> Rect2 (global), used to pick the
##                                  hand card nearest a "hand" edge's source;
##                                  invalid/missing rects fall back to list
##                                  order (hand_0)
static func build(ctx: Dictionary) -> Dictionary:
	var mobile: bool = ctx.get("mobile", false)
	var hand_count: int = ctx.get("hand_count", 0)
	var opp_hand_count: int = ctx.get("opp_hand_count", 0)
	var hand_at_top: bool = ctx.get("hand_at_top", false)
	var tracker_count: int = ctx.get("tracker_count", 0)
	var choice_count: int = ctx.get("choice_count", 0)
	var stack_count: int = ctx.get("stack_count", 0)
	var hint_count: int = ctx.get("hint_count", 0)
	var zone_jail_side: String = ctx.get("zone_jail_side", "")
	var rect_of: Callable = ctx.get("rect_of", Callable())

	# Geometric slot assignment: hand_<i> keeps the acting-hand semantics,
	# but each row is wired to the board edge its fan physically sits on.
	var bottom_prefix := "opp_hand" if hand_at_top else "hand"
	var top_prefix := "hand" if hand_at_top else "opp_hand"
	var bottom_count := opp_hand_count if hand_at_top else hand_count
	var top_count := hand_count if hand_at_top else opp_hand_count

	var map := _merge(_copy_table(PLAYMAT), MOBILE_UI if mobile else DESKTOP_UI)
	if zone_jail_side != "":
		_apply_zone_jail(map, zone_jail_side)
	_add_fan_row(map, bottom_prefix, bottom_count, true, mobile)
	_add_fan_row(map, top_prefix, top_count, false, mobile)
	_add_tracker_column(map, tracker_count, mobile)
	_add_choice_column(map, choice_count, stack_count)
	_add_stack_column(map, stack_count, choice_count)
	_add_hint_row(map, hint_count, bottom_prefix, bottom_count)
	# Mobile: the log panel and tracker live in slide-out trays — reachable
	# via the bumpers only, never by walking off the board.
	_expand_sentinels(map, bottom_prefix, bottom_count, top_prefix, top_count,
			0 if mobile else tracker_count, rect_of)
	if bottom_count <= 0:
		_add_empty_hand_return(map)
	if mobile:
		_strip_target(map, "log_panel")
		_strip_target(map, "sys_save")
	return map


## Ids of the hand row for `count` cards (left to right).
static func hand_ids(count: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(count):
		out.append("hand_%d" % i)
	return out


## Ids of the opponent hand row for `count` cards (left to right).
static func opp_hand_ids(count: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(count):
		out.append("opp_hand_%d" % i)
	return out


static func tracker_ids(count: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(count):
		out.append("trk_%d" % i)
	return out


static func choice_ids(count: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(count):
		out.append("choice_%d" % i)
	return out


static func stack_ids(count: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(count):
		out.append("stack_%d" % i)
	return out


static func hint_ids(count: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(count):
		out.append("hint_%d" % i)
	return out


static func _copy_table(table: Dictionary) -> Dictionary:
	var out := {}
	for id: String in table:
		var entry: Dictionary = table[id]
		var copy := {}
		for dir: String in entry:
			copy[dir] = (entry[dir] as Array).duplicate()
		out[id] = copy
	return out


## Merge `extra` into `base`: new ids are copied in, shared ids get their
## direction lists appended (no duplicates).
static func _merge(base: Dictionary, extra: Dictionary) -> Dictionary:
	for id: String in extra:
		if not base.has(id):
			base[id] = {}
		var entry: Dictionary = base[id]
		var add: Dictionary = extra[id]
		for dir: String in add:
			if not entry.has(dir):
				entry[dir] = []
			for target: String in add[dir]:
				if target not in (entry[dir] as Array):
					(entry[dir] as Array).append(target)
	return base


## Replace the eight `<side>_z*` entries with ZONE_JAIL_EDGES (directions
## flipped on both axes for the mirrored top playmat). Replacement, not
## merge: the free-browse exits (rage/hand/deck) must vanish so the wrap
## edges are the ones a jailed left/right/up/down actually follows.
static func _apply_zone_jail(map: Dictionary, side: String) -> void:
	for zone: int in ZONE_JAIL_EDGES:
		var edges: Dictionary = ZONE_JAIL_EDGES[zone]
		var entry := {}
		for dir: String in edges:
			var out_dir: String = _FLIP[dir] if side == "top" else dir
			var targets: Array = []
			for target: String in edges[dir]:
				targets.append("%s_%s" % [side, target])
			entry[out_dir] = targets
		map["%s_z%d" % [side, zone]] = entry


## One fanned-card row in a geometric slot. Bottom slot: cards climb up
## into the bottom board (HAND_EXITS), rightmost exits onto the sort/toggle
## pocket. Top slot: the vertical directions flip — `up` dead-ends at the
## screen edge, `down` enters the top board (OPP_HAND_EXITS), rightmost
## exits onto the opponent hand-button stack (desktop only — MOBILE_UI has
## no opponent stack). The `prefix` decides which id family fills the slot.
static func _add_fan_row(map: Dictionary, prefix: String, count: int, bottom: bool, mobile: bool) -> void:
	var right_exit: Array
	if bottom:
		right_exit = ["ap_sort_hand"] if not mobile else ["ap_sort_hand", "ap_cancel"]
	else:
		right_exit = [] if mobile else ["ap_opp_hand_toggle"]
	for i in range(count):
		map["%s_%d" % [prefix, i]] = {
			"up": HAND_EXITS.duplicate() if bottom else [],
			"right": ["%s_%d" % [prefix, i + 1]] if i < count - 1 else right_exit.duplicate(),
			"down": [] if bottom else OPP_HAND_EXITS.duplicate(),
			"left": ["%s_%d" % [prefix, i - 1]] if i > 0 else [],
		}


## With an empty hand there are no hand cards to carry the cursor back up to
## the board, yet _expand_sentinels made every bottom-row zone's "down" edge
## land on ap_sort_hand. Give the sort/toggle pocket the hand row's return
## exits (HAND_EXITS) so the cursor can climb back out instead of being
## trapped on the two buttons (the action-panel play buttons to their right
## are hidden during effect resolution). Appended, not prepended, so the
## no-history default up-edge (sort -> toggle) stands.
static func _add_empty_hand_return(map: Dictionary) -> void:
	for id: String in ["ap_sort_hand", "ap_hand_toggle"]:
		if not map.has(id):
			continue
		var up: Array = map[id]["up"]
		for board_exit: String in HAND_EXITS:
			if board_exit not in up:
				up.append(board_exit)


static func _add_tracker_column(map: Dictionary, count: int, mobile: bool) -> void:
	var board_exits: Array = [] if mobile else ["bot_deck", "bot_discard", "top_monster_deck", "top_strategy_1"]
	for i in range(count):
		map["trk_%d" % i] = {
			"up": ["trk_%d" % (i - 1)] if i > 0 else ([] if mobile else ["sys_export_log"]),
			"right": [],
			"down": ["trk_%d" % (i + 1)] if i < count - 1 else ([] if mobile else ["ap_cancel", "ap_confirm"]),
			"left": board_exits.duplicate(),
		}


static func _add_choice_column(map: Dictionary, count: int, stack_count: int = 0) -> void:
	for i in range(count):
		var up: Array = ["choice_%d" % (i - 1)] if i > 0 \
				else (["stack_%d" % (stack_count - 1)] if stack_count > 0 else [])
		map["choice_%d" % i] = {
			"up": up,
			"right": [],
			"down": ["choice_%d" % (i + 1)] if i < count - 1 else [],
			"left": [],
		}


## Pending-effect rows: a vertical column on the top-right edge. The bottom
## row chains into the choice column when a choice prompt is open; the only
## other ways in are the Select toggle and walking left off the top board's
## right edge (free browse) — no board element points AT the stack, so the
## right-edge lanes are unchanged when no rows exist.
static func _add_stack_column(map: Dictionary, count: int, choice_count: int) -> void:
	for i in range(count):
		var down: Array = ["stack_%d" % (i + 1)] if i < count - 1 \
				else (["choice_0"] if choice_count > 0 else [])
		map["stack_%d" % i] = {
			"up": ["stack_%d" % (i - 1)] if i > 0 else [],
			"right": [],
			"down": down,
			"left": ["top_monster_deck", "top_z1"],
		}


## Prompt-preview mini cards (effect source / placed card / sticky
## pending-effect slot): a horizontal row pinned above the action prompt at
## the bottom-left — LEFT of bot row 2 (level with the monster zone), below
## the log panel, above-left of the hand fan. Right walks onto the board's
## left edge, down enters the hand; up reaches the log (one-way — on the log
## the dpad scrolls, same as sys_save's edge; mobile's build() strips it,
## the tray is bumper-only). Runs BEFORE _expand_sentinels so the "hand"
## edges expand to the nearest card; no ids exist when the row is down, so
## every lane it touches is unchanged then.
static func _add_hint_row(map: Dictionary, count: int, bottom_prefix: String, bottom_count: int) -> void:
	for i in range(count):
		map["hint_%d" % i] = {
			"up": ["log_panel"],
			"right": ["hint_%d" % (i + 1)] if i < count - 1 else ["bot_monster_deck", "bot_z1"],
			"down": [HAND_SENTINEL],
			"left": ["hint_%d" % (i - 1)] if i > 0 else [],
		}
	if count <= 0:
		return
	# Ways in: left off the board's left end and off the bottom fan's first
	# card (appended — history returns the cursor where it came from).
	(map["bot_monster_deck"]["left"] as Array).append("hint_%d" % (count - 1))
	if bottom_count > 0:
		(map["%s_0" % bottom_prefix]["left"] as Array).append("hint_%d" % (count - 1))


## Replace the "hand", "opp_hand" and "tracker" sentinels in every edge
## list. The fan sentinels are GEOMETRIC slots ("hand" = the fan below the
## bottom row, "opp_hand" = the fan above the top row) and become the
## single card of the slot's id family nearest (center X) the source
## element — entering a fan from Z5 lands on a right-side card, from Z1 on
## a left-side one. An empty bottom fan falls back to ap_sort_hand; an
## empty top fan drops its sentinel with no fallback (nothing above the
## top row can trap the cursor).
static func _expand_sentinels(map: Dictionary, bottom_prefix: String, bottom_count: int,
		top_prefix: String, top_count: int, tracker_count: int, rect_of: Callable) -> void:
	var trk: Array[String] = tracker_ids(tracker_count)
	for id: String in map:
		var entry: Dictionary = map[id]
		for dir: String in entry:
			var targets: Array = entry[dir]
			var hand_at := targets.find(HAND_SENTINEL)
			if hand_at >= 0:
				targets.remove_at(hand_at)
				if bottom_count <= 0:
					if "ap_sort_hand" not in targets and id != "ap_sort_hand":
						targets.append("ap_sort_hand")
				else:
					targets.insert(hand_at, _nearest_fan_id(id, bottom_prefix, bottom_count, rect_of))
			var opp_at := targets.find(OPP_HAND_SENTINEL)
			if opp_at >= 0:
				targets.remove_at(opp_at)
				if top_count > 0:
					targets.insert(opp_at, _nearest_fan_id(id, top_prefix, top_count, rect_of))
			var trk_at := targets.find(TRACKER_SENTINEL)
			if trk_at >= 0:
				targets.remove_at(trk_at)
				for trk_id in trk:
					if trk_id not in targets:
						targets.append(trk_id)


static func _strip_target(map: Dictionary, target: String) -> void:
	for id: String in map:
		var entry: Dictionary = map[id]
		for dir: String in entry:
			(entry[dir] as Array).erase(target)


static func _nearest_fan_id(source_id: String, prefix: String, count: int, rect_of: Callable) -> String:
	if not rect_of.is_valid():
		return "%s_0" % prefix
	var source_rect: Rect2 = rect_of.call(source_id)
	if source_rect.size == Vector2.ZERO:
		return "%s_0" % prefix
	var source_x := source_rect.get_center().x
	var best := 0
	var best_dist := INF
	for i in range(count):
		var rect: Rect2 = rect_of.call("%s_%d" % [prefix, i])
		if rect.size == Vector2.ZERO:
			continue
		var dist: float = absf(rect.get_center().x - source_x)
		if dist < best_dist:
			best_dist = dist
			best = i
	return "%s_%d" % [prefix, best]
