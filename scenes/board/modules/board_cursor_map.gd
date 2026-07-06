class_name BoardCursorMap
extends RefCounted
## The controller cursor's navigation map for the game board — a direct
## transcription of the annotated playmat layout, consumed by CursorMap
## (scripts/input/cursor_map.gd).
##
## EDIT THIS TABLE to change where the cursor travels: each element lists
## its up/right/down/left targets. Multiple candidates in one direction are
## tie-broken by the last-10-visited history (the cursor "returns where it
## came from"), then list order. GamepadBoardNav skips hidden/invalid
## elements transparently, so e.g. the hidden Strategy3 never blocks a lane.
##
## Element ids are VISUAL (seat-independent): `bot_*` = the bottom playmat,
## `top_*` = the opponent playmat at the top, plus the special `hand`.
## The top board is anchor-mirrored on both axes, hence its flipped rows:
##
##   top r1:  discard | z5 | z4 | z3 | z2 | z1 | monster_deck
##   top r2:  deck    | z6 | z7 | z8 | rage | strategy(1 over 0)
##   bot r1:  strategy(0 over 1) | rage | z8 | z7 | z6 | deck
##   bot r2:  monster_deck | z1 | z2 | z3 | z4 | z5 | discard
##   hand:    below bot r2
##
## Kinds: z1..z8 (zone_slots[0..7]), strategy_0..2 (strategy_slots),
## rage (rage_display), deck (DeckInfo), monster_deck (MonsterInfo),
## discard (DiscardInfo). The monster CARD rides its zone slot.

## Module-to-module edges: when element navigation dead-ends at a group's
## boundary, the cursor hops to the neighboring GROUP (entering at its most
## recently visited element). Rearranging modules only means re-pointing
## these edges.
const GROUPS := {
	"board": {"up": [], "right": [], "down": ["hand"], "left": []},
	"hand": {"up": ["board"], "right": ["action_panel"], "down": [], "left": []},
	"action_panel": {"up": [], "right": [], "down": ["hand"], "left": ["hand"]},
}

## Element id -> group; unlisted elements default to "board".
const MEMBERSHIP := {
	"hand": "hand",
}

const MAP := {
	# --- Top board, row 1 (screen top) ---
	"top_discard": {"up": [], "right": ["top_z5"], "down": ["top_deck"], "left": []},
	"top_z5": {"up": [], "right": ["top_z4"], "down": ["top_z6"], "left": ["top_discard"]},
	"top_z4": {"up": [], "right": ["top_z3"], "down": ["top_z7"], "left": ["top_z5"]},
	"top_z3": {"up": [], "right": ["top_z2"], "down": ["top_z8"], "left": ["top_z4"]},
	"top_z2": {"up": [], "right": ["top_z1"], "down": ["top_rage"], "left": ["top_z3"]},
	"top_z1": {"up": [], "right": ["top_monster_deck"], "down": ["top_strategy_1"], "left": ["top_z2"]},
	"top_monster_deck": {"up": [], "right": [], "down": ["top_strategy_0", "top_strategy_1"], "left": ["top_z1"]},

	# --- Top board, row 2 (nearer the divider) ---
	"top_deck": {"up": ["top_discard"], "right": ["top_z6"], "down": ["bot_strategy_0", "bot_rage"], "left": []},
	"top_z6": {"up": ["top_z5"], "right": ["top_z7"], "down": ["bot_rage"], "left": ["top_deck"]},
	"top_z7": {"up": ["top_z4"], "right": ["top_z8"], "down": ["bot_z8"], "left": ["top_z6"]},
	"top_z8": {"up": ["top_z3"], "right": ["top_rage"], "down": ["bot_z7"], "left": ["top_z7"]},
	"top_rage": {"up": ["top_z2"], "right": ["top_strategy_1"], "down": ["bot_z6"], "left": ["top_z8"]},
	# Mirrored strategy column: strategy_1 sits ABOVE strategy_0 on the top board.
	"top_strategy_1": {"up": ["top_z1", "top_monster_deck"], "right": [], "down": ["top_strategy_0"], "left": ["top_rage"]},
	"top_strategy_0": {"up": ["top_strategy_1"], "right": [], "down": ["bot_deck"], "left": ["top_rage"]},
	"top_strategy_2": {"up": ["top_strategy_0"], "right": [], "down": ["bot_deck"], "left": ["top_rage"]},

	# --- Bottom board, row 1 (nearer the divider) ---
	"bot_strategy_0": {"up": ["top_deck"], "right": ["bot_rage"], "down": ["bot_strategy_1"], "left": []},
	"bot_strategy_1": {"up": ["bot_strategy_0"], "right": ["bot_rage"], "down": ["bot_monster_deck", "bot_z1"], "left": []},
	"bot_strategy_2": {"up": ["bot_strategy_1"], "right": ["bot_rage"], "down": ["bot_monster_deck", "bot_z1"], "left": []},
	"bot_rage": {"up": ["top_z6"], "right": ["bot_z8"], "down": ["bot_z1", "bot_z2"], "left": ["bot_strategy_0"]},
	"bot_z8": {"up": ["top_z7"], "right": ["bot_z7"], "down": ["bot_z3"], "left": ["bot_rage"]},
	"bot_z7": {"up": ["top_z8"], "right": ["bot_z6"], "down": ["bot_z4"], "left": ["bot_z8"]},
	"bot_z6": {"up": ["top_rage"], "right": ["bot_deck"], "down": ["bot_z5"], "left": ["bot_z7"]},
	"bot_deck": {"up": ["top_strategy_0"], "right": [], "down": ["bot_discard"], "left": ["bot_z6"]},

	# --- Bottom board, row 2 ---
	"bot_monster_deck": {"up": ["bot_strategy_1"], "right": ["bot_z1"], "down": ["hand"], "left": []},
	"bot_z1": {"up": ["bot_rage"], "right": ["bot_z2"], "down": ["hand"], "left": ["bot_monster_deck"]},
	"bot_z2": {"up": ["bot_rage"], "right": ["bot_z3"], "down": ["hand"], "left": ["bot_z1"]},
	"bot_z3": {"up": ["bot_z8"], "right": ["bot_z4"], "down": ["hand"], "left": ["bot_z2"]},
	"bot_z4": {"up": ["bot_z7"], "right": ["bot_z5"], "down": ["hand"], "left": ["bot_z3"]},
	"bot_z5": {"up": ["bot_z6"], "right": ["bot_discard"], "down": ["hand"], "left": ["bot_z4"]},
	"bot_discard": {"up": ["bot_deck"], "right": [], "down": ["hand"], "left": ["bot_z5"]},

	# --- Hand (per-card movement handled by GamepadBoardNav; up exits to
	# wherever the cursor entered from, courtesy of the history tiebreak) ---
	"hand": {
		"up": ["bot_z2", "bot_z3", "bot_z1", "bot_z4", "bot_z5", "bot_monster_deck", "bot_discard"],
		"right": [], "down": [], "left": [],
	},
}
