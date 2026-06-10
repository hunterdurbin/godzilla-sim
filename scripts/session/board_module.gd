class_name BoardModule

## Static helpers for modules dropped into a GameBoard scene tree.
##
## A "module" is any node a designer adds as a child somewhere under the
## GameBoard root — overlays, HUD components, custom action panels, etc.
## In its _ready() it can locate the GameSession / EffectUIRouter /
## MultiplayerSync without needing the parent scene's controller script
## to wire it manually.
##
## Cross-scene contract: every GameBoard scene that wants multiplayer must
## have its root node named "GameBoard" with a `GameSession/MultiplayerSync`
## subtree (and `GameSession/EffectUIRouter` if it consumes effect prompts).
## The .tscn file name and visuals can differ — only the named subtree must
## match between peers so RPCs route correctly.
##
## Usage from any module:
##   func _ready() -> void:
##       var router := BoardModule.find_router(self)
##       if router:
##           router.register_handler("deck_search", _show)


## Walk up to the GameBoard root, then down to GameSession.
## Returns null + push_warning if the contract is violated.
static func find_session(node: Node) -> GameSession:
	var root := node.find_parent("GameBoard")
	if root == null:
		push_warning("[BoardModule] No 'GameBoard' ancestor found for %s. Every GameBoard scene's root node must be named 'GameBoard'." % node.get_path())
		return null
	var session := root.get_node_or_null("GameSession")
	if session == null:
		push_warning("[BoardModule] GameBoard root is missing 'GameSession' child. Required scene-tree contract.")
		return null
	return session as GameSession


## Find the EffectUIRouter for this scene tree, or null if not present.
static func find_router(node: Node) -> EffectUIRouter:
	var session := find_session(node)
	if session == null:
		return null
	return session.get_node_or_null("EffectUIRouter") as EffectUIRouter


## Find the MultiplayerSync for this scene tree, or null if not present.
## Modules rarely need this directly — RPC traffic routes through router.
static func find_multiplayer_sync(node: Node) -> MultiplayerSync:
	var session := find_session(node)
	if session == null:
		return null
	return session.get_node_or_null("MultiplayerSync") as MultiplayerSync


## Walk up to the nearest SeatContainer ancestor. If found, the module
## should use `seat.get_player_id()` instead of its own `@export player_id`.
## Returns null if no SeatContainer is in the ancestor chain — module
## then falls back to its inspector-configured player_id.
##
## Walks up the parent chain (NOT through find_parent("GameBoard")) — seat
## containers can be at any depth under the board root.
static func find_seat(node: Node) -> SeatContainer:
	var n := node.get_parent()
	while n:
		if n is SeatContainer:
			return n as SeatContainer
		n = n.get_parent()
	return null


## Locate the Card prefab to instantiate for any module that renders cards
## (overlays, hand managers, etc.). Reads from the GameBoard's PlayerBoard
## descendant — `card_scene` is `@export`-able there so a designer can swap
## prefabs per-board variant. Falls back to the default Card.tscn when no
## PlayerBoard is reachable (spectator scene, ReplayViewer, etc.).
static func get_card_scene(node: Node) -> PackedScene:
	var board := node.find_parent("GameBoard")
	if board:
		for child in board.find_children("*", "PlayerBoard", true, false):
			if "card_scene" in child and child.card_scene:
				return child.card_scene
	return preload("res://scenes/cards/Card.tscn")
