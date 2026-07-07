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
## Two sentinels may appear in edge lists and are expanded by build():
##   "hand"    -> the hand card nearest (center X) to the source element,
##                or ap_sort_hand when the hand is empty
##   "tracker" -> every trk_<i> label (history picks where you left off)
##
## While a zone prompt jails the cursor (ctx key `zone_jail_side`), the
## target playmat's z1-z8 swap to the ZONE_JAIL_EDGES table — wrap-around
## rows so all eight zones stay reachable without the rage/hand/deck exits.
##
## Element ids are VISUAL (seat-independent): `bot_*` = the bottom playmat,
## `top_*` = the opponent playmat at the top. Dynamic ids: hand_<i> (fanned
## cards, left to right), trk_<i> (turn-tracker labels, top to bottom),
## choice_<i> (choice-prompt buttons, top to bottom), stack_<i>
## (pending-effect rows, top to bottom — chained to choice_0 when a choice
## is open, otherwise entered via the Select toggle or from the top board).
## Button ids: ap_* = action panel + hand stacks + mobile FAB, sys_* = the
## corner utility column, log_panel = the game log/chat panel.
##
## @tool-safe and scene-free: build() is a pure function of the ctx
## Dictionary, so unit tests and the editor overlay feed it fake data.

const HAND_SENTINEL := "hand"
const TRACKER_SENTINEL := "tracker"

## Exits used for `up` from every hand card (history returns the cursor to
## wherever it entered the hand from).
const HAND_EXITS: Array[String] = [
	"bot_z2", "bot_z3", "bot_z1", "bot_z4", "bot_z5",
	"bot_monster_deck", "bot_discard",
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
	"top_discard": {"up": [], "right": ["top_z5"], "down": ["top_deck"], "left": ["log_panel"]},
	"top_z5": {"up": [], "right": ["top_z4"], "down": ["top_z6"], "left": ["top_discard"]},
	"top_z4": {"up": [], "right": ["top_z3"], "down": ["top_z7"], "left": ["top_z5"]},
	"top_z3": {"up": [], "right": ["top_z2"], "down": ["top_z8"], "left": ["top_z4"]},
	"top_z2": {"up": [], "right": ["top_z1"], "down": ["top_rage"], "left": ["top_z3"]},
	"top_z1": {"up": [], "right": ["top_monster_deck"], "down": ["top_strategy_1"], "left": ["top_z2"]},
	"top_monster_deck": {"up": [], "right": ["ap_opp_hand_toggle", "sys_bug_report"], "down": ["top_strategy_0", "top_strategy_1"], "left": ["top_z1"]},

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

## Zone-only edges swapped in while a zone prompt jails the cursor (ctx key
## `zone_jail_side`): both zone rows chain with wrap-around at the ends
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

	# Opponent hand stack (hotseat only; hidden -> traversed through). Also a
	# vertical column, top-right: toggle above sort.
	"ap_opp_hand_toggle": {"up": [], "right": ["sys_bug_report"], "down": ["ap_opp_sort_hand"], "left": ["top_monster_deck"]},
	"ap_opp_sort_hand": {"up": ["ap_opp_hand_toggle"], "right": ["sys_bug_report"], "down": ["top_strategy_1"], "left": ["top_monster_deck"]},

	# Corner utility column (top-right edge, top to bottom).
	"sys_bug_report": {"up": [], "right": [], "down": ["sys_concede"], "left": ["ap_opp_sort_hand", "top_monster_deck"]},
	"sys_concede": {"up": ["sys_bug_report"], "right": [], "down": ["sys_main_menu"], "left": ["top_monster_deck"]},
	"sys_main_menu": {"up": ["sys_concede"], "right": [], "down": ["sys_sound"], "left": ["top_monster_deck"]},
	"sys_sound": {"up": ["sys_main_menu"], "right": [], "down": ["sys_music"], "left": ["top_strategy_1"]},
	"sys_music": {"up": ["sys_sound"], "right": [], "down": ["sys_export_log"], "left": ["top_strategy_1"]},
	"sys_export_log": {"up": ["sys_music"], "right": [], "down": ["tracker"], "left": ["top_strategy_1"]},

	# Game log / chat panel (left edge, vertically centered).
	"log_panel": {"up": [], "right": ["top_deck", "bot_strategy_0", "bot_strategy_1", "top_discard"], "down": [], "left": []},
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
##   hand_count: int (0)          — fanned cards in the local hand
##   tracker_count: int (0)       — interactive turn-tracker labels
##   choice_count: int (0)        — visible choice-prompt buttons
##   stack_count: int (0)         — visible pending-effect rows
##   zone_jail_side: String ("")  — "bot"/"top" while a zone prompt is up:
##                                  that playmat's z1-z8 get the
##                                  ZONE_JAIL_EDGES wrap-around edges instead
##                                  of their free-browse rows
##   rect_of: Callable (invalid)  — id -> Rect2 (global), used to pick the
##                                  hand card nearest a "hand" edge's source;
##                                  invalid/missing rects fall back to list
##                                  order (hand_0)
static func build(ctx: Dictionary) -> Dictionary:
	var mobile: bool = ctx.get("mobile", false)
	var hand_count: int = ctx.get("hand_count", 0)
	var tracker_count: int = ctx.get("tracker_count", 0)
	var choice_count: int = ctx.get("choice_count", 0)
	var stack_count: int = ctx.get("stack_count", 0)
	var zone_jail_side: String = ctx.get("zone_jail_side", "")
	var rect_of: Callable = ctx.get("rect_of", Callable())

	var map := _merge(_copy_table(PLAYMAT), MOBILE_UI if mobile else DESKTOP_UI)
	if zone_jail_side != "":
		_apply_zone_jail(map, zone_jail_side)
	_add_hand_row(map, hand_count, mobile)
	_add_tracker_column(map, tracker_count, mobile)
	_add_choice_column(map, choice_count, stack_count)
	_add_stack_column(map, stack_count, choice_count)
	# Mobile: the log panel and tracker live in slide-out trays — reachable
	# via the bumpers only, never by walking off the board.
	_expand_sentinels(map, hand_count, 0 if mobile else tracker_count, rect_of)
	if mobile:
		_strip_target(map, "log_panel")
	return map


## Ids of the hand row for `count` cards (left to right).
static func hand_ids(count: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(count):
		out.append("hand_%d" % i)
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


static func _add_hand_row(map: Dictionary, count: int, mobile: bool) -> void:
	var right_exit: Array = ["ap_sort_hand"] if not mobile else ["ap_sort_hand", "ap_cancel"]
	for i in range(count):
		map["hand_%d" % i] = {
			"up": HAND_EXITS.duplicate(),
			"right": ["hand_%d" % (i + 1)] if i < count - 1 else right_exit.duplicate(),
			"down": [],
			"left": ["hand_%d" % (i - 1)] if i > 0 else [],
		}


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


## Replace the "hand" and "tracker" sentinels in every edge list. "hand"
## becomes the single card nearest (center X) the source element — entering
## the hand from Z5 lands on a right-side card, from Z1 on a left-side one.
static func _expand_sentinels(map: Dictionary, hand_count: int, tracker_count: int, rect_of: Callable) -> void:
	var trk: Array[String] = tracker_ids(tracker_count)
	for id: String in map:
		var entry: Dictionary = map[id]
		for dir: String in entry:
			var targets: Array = entry[dir]
			var hand_at := targets.find(HAND_SENTINEL)
			if hand_at >= 0:
				targets.remove_at(hand_at)
				if hand_count <= 0:
					if "ap_sort_hand" not in targets and id != "ap_sort_hand":
						targets.append("ap_sort_hand")
				else:
					targets.insert(hand_at, _nearest_hand_id(id, hand_count, rect_of))
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


static func _nearest_hand_id(source_id: String, hand_count: int, rect_of: Callable) -> String:
	if not rect_of.is_valid():
		return "hand_0"
	var source_rect: Rect2 = rect_of.call(source_id)
	if source_rect.size == Vector2.ZERO:
		return "hand_0"
	var source_x := source_rect.get_center().x
	var best := 0
	var best_dist := INF
	for i in range(hand_count):
		var rect: Rect2 = rect_of.call("hand_%d" % i)
		if rect.size == Vector2.ZERO:
			continue
		var dist: float = absf(rect.get_center().x - source_x)
		if dist < best_dist:
			best_dist = dist
			best = i
	return "hand_%d" % best
