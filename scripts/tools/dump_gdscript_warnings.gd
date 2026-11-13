extends SceneTree

## Compiles every project GDScript (scripts/, scenes/, tests/) so the engine
## prints its GDScript warnings, then prints DUMP_GDSCRIPT_WARNINGS_DONE.
## Driven by check_gdscript_warnings.py, which parses the output.
##
## Usage: <godot> --headless --path . --script scripts/tools/dump_gdscript_warnings.gd

const ROOTS: Array[String] = ["res://scripts", "res://scenes", "res://tests"]
const DONE_MARKER := "DUMP_GDSCRIPT_WARNINGS_DONE"


var _done := false


func _process(_delta: float) -> bool:
	# First frame: autoloads are registered by now, so scripts that name them
	# compile.
	if _done:
		return true
	_done = true
	var paths: Array[String] = []
	for base in ROOTS:
		_collect(base, paths)
	for path in paths:
		ResourceLoader.load(path)
	print("%s %d" % [DONE_MARKER, paths.size()])
	quit(0)
	return true


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
