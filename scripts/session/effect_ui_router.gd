class_name EffectUIRouter
extends Node

## Bridges EffectHandler request signals to overlay scenes.
##
## Phase 3 status: SKELETON. The full router intercepts every
## effect_handler.X_requested signal, instantiates a registered overlay
## scene, awaits its result, and calls effect_handler.resolve_X(...) back.
## For now, game_board.gd still owns the overlay UI inline; this router
## exists so a new GameBoard scene can register its own overlay scenes
## without re-implementing the request/resolve handshake glue.
##
## Once overlay-per-scene migration completes, the body of this script
## will host the dispatcher and the inline _show_*/_on_* handlers in
## game_board.gd will go away.

const OVERLAY_KEYS := [
	"deck_search",
	"deck_arrange",
	"card_select",
	"hand_discard",
	"hand_card_select",
	"zone_target",
	"strategy_target",
	"choice",
	"discard_view",
	"monster_deck_view",
	"zone_stack_view",
	"card_zoom",
]

var _registered_overlays: Dictionary = {}

var _board: Node
var _session: Node


func _ready() -> void:
	_session = get_parent()
	if _session:
		_board = _session.get_parent()


## Register a PackedScene for an overlay key (see OVERLAY_KEYS).
## In the stub phase this just stores the registration; the dispatcher is
## not yet wired. A new GameBoard scene that wants to use the router fully
## should register its overlays here in _ready().
func register_overlay(key: String, scene: PackedScene) -> void:
	if not OVERLAY_KEYS.has(key):
		push_warning("[EffectUIRouter] Unknown overlay key: %s" % key)
		return
	_registered_overlays[key] = scene


## True if a scene is registered for the given key.
func has_overlay(key: String) -> bool:
	return _registered_overlays.has(key)


## Returns the registered PackedScene for the key, or null if none.
func get_overlay_scene(key: String) -> PackedScene:
	return _registered_overlays.get(key, null)
