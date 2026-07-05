extends Node

## Spike: prove that two SceneMultiplayer branch APIs in one process, with
## DIFFERING absolute branch roots, can exchange RPCs because node paths are
## encoded relative to each API's root_path. This is the keystone mechanism
## for the dedicated server's per-room routing (one room = one branch API).
##
## Run: godot --headless --path . res://tests/harness/BranchRpcSpike.tscn
## Exits 0 on PASS, 1 on FAIL.

const PORT := 34567
const SYNC_SCRIPT := preload("res://tests/harness/spike_sync.gd")

var _server_got := false
var _client_got := false


func _ready() -> void:
	# The two sides deliberately sit at different depths so their ABSOLUTE
	# paths differ; only the paths relative to each branch root match.
	var server_root := Node.new()
	server_root.name = "ServerSide"
	add_child(server_root)
	var rooms := Node.new()
	rooms.name = "Rooms"
	server_root.add_child(rooms)
	var room := Node.new()
	room.name = "R_TEST"
	rooms.add_child(room)

	var client_root := Node.new()
	client_root.name = "ClientSide"
	add_child(client_root)

	# Branch APIs must be registered before the RPC nodes enter the tree.
	var server_api := SceneMultiplayer.new()
	var server_peer := ENetMultiplayerPeer.new()
	var err := server_peer.create_server(PORT)
	assert(err == OK)
	server_api.multiplayer_peer = server_peer
	get_tree().set_multiplayer(server_api, room.get_path())

	var client_api := SceneMultiplayer.new()
	var client_peer := ENetMultiplayerPeer.new()
	err = client_peer.create_client("127.0.0.1", PORT)
	assert(err == OK)
	client_api.multiplayer_peer = client_peer
	get_tree().set_multiplayer(client_api, client_root.get_path())

	var server_sync := _build_chain(room)
	var client_sync := _build_chain(client_root)
	server_sync.got_ping.connect(func(text: String) -> void:
		print("[spike] server received: ", text)
		_server_got = true)
	client_sync.got_ping.connect(func(text: String) -> void:
		print("[spike] client received: ", text)
		_client_got = true)

	server_api.peer_connected.connect(func(id: int) -> void:
		print("[spike] server sees peer ", id)
		server_sync.ping.rpc_id(id, "hello from server room branch"))
	client_api.connected_to_server.connect(func() -> void:
		print("[spike] client connected as ", client_api.get_unique_id())
		client_sync.ping.rpc_id(1, "hello from client branch"))

	# Wait up to ~5 seconds for both directions.
	for i in range(300):
		await get_tree().process_frame
		if _server_got and _client_got:
			print("SPIKE PASS: branch-relative RPC routing works both ways")
			get_tree().quit(0)
			return
	print("SPIKE FAIL: timed out (server_got=%s client_got=%s)" % [_server_got, _client_got])
	get_tree().quit(1)


func _build_chain(parent: Node) -> Node:
	var board := Node.new()
	board.name = "GameBoard"
	parent.add_child(board)
	var session := Node.new()
	session.name = "GameSession"
	board.add_child(session)
	var sync := Node.new()
	sync.name = "MultiplayerSync"
	sync.set_script(SYNC_SCRIPT)
	session.add_child(sync)
	return sync
