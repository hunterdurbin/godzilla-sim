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
