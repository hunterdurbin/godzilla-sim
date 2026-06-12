extends Control

## Smoke test for the REAL online client path: NetworkManager.connect_to_server
## -> create/join -> deck -> START -> loads the real GameBoard scene (this
## node is replaced by the scene change). Validates Mode.ONLINE end-to-end up
## to the first-player prompt; success is judged by the runner grepping logs
## (state applied, no SCRIPT ERRORs) since the board then waits for input.
##
## Run (after ServerMain):
##   godot --headless --path . scenes/server/tests/RealClientSmoke.tscn -- --create
##   godot --headless --path . scenes/server/tests/RealClientSmoke.tscn -- --join

const CODE_FILE := "/tmp/godzilla_test_room_code.txt"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var is_creator := "--create" in args
	if is_creator and FileAccess.file_exists(CODE_FILE):
		DirAccess.remove_absolute(CODE_FILE)

	NetworkManager.server_host = "127.0.0.1"
	NetworkManager.server_room_created.connect(func(code: String) -> void:
		print("[RealSmoke] room created: %s" % code)
		var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
		f.store_string(code)
		f.close())
	NetworkManager.server_seated.connect(func(_room: String, pid: int) -> void:
		print("[RealSmoke] seated as player %d" % pid)
		var decks := DecklistManager.get_all_decklists()
		DecklistManager.select_deck_for_player(pid, decks[0])
		NetworkManager.send_deck_to_server(decks[0]))
	NetworkManager.server_error.connect(func(code: String) -> void:
		push_error("[RealSmoke] server error: %s" % code)
		get_tree().quit(1))

	var err := await NetworkManager.connect_to_server()
	if err != OK:
		push_error("[RealSmoke] connect failed: %d" % err)
		get_tree().quit(1)
		return
	print("[RealSmoke] connected (%s)" % ("creator" if is_creator else "joiner"))

	if is_creator:
		NetworkManager.create_room(false, "")
	else:
		var code := ""
		for i in range(60):
			if FileAccess.file_exists(CODE_FILE):
				var f := FileAccess.open(CODE_FILE, FileAccess.READ)
				code = f.get_as_text().strip_edges()
				f.close()
				if not code.is_empty():
					break
			await get_tree().create_timer(0.25).timeout
		if code.is_empty():
			push_error("[RealSmoke] no room code")
			get_tree().quit(1)
			return
		NetworkManager.join_room(code)
	# From here NetworkManager handles START -> GameBoard scene change.
