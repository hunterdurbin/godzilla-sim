@tool
extends EditorScript
## Consistency lint for the hand-edited BoardNavGraph tables. Run from the
## Script Editor (File > Run). Reports, per layout:
##   - dangling targets (edge points at an id that is not a node)
##   - asymmetric edges (A.right -> B without B.left -> A) — often
##     intentional (one-way lanes), so these are warnings, not errors
##   - unreachable nodes (no edge from anywhere points at them)
##
## Builds with representative dynamic counts so the hand/tracker/choice rows
## are checked too.

const OPPOSITE := {"up": "down", "down": "up", "left": "right", "right": "left"}


func _run() -> void:
	for layout in ["desktop", "mobile"]:
		var graph := BoardNavGraph.build({
			"mobile": layout == "mobile",
			"hand_count": 3,
			"tracker_count": 2,
			"choice_count": 0,
		})
		print("\n=== BoardNavGraph audit: %s (%d nodes) ===" % [layout, graph.size()])
		_audit(graph)


func _audit(graph: Dictionary) -> void:
	var referenced := {}
	var dangling := 0
	var asymmetric := 0
	for id: String in graph:
		for dir: String in ["up", "right", "down", "left"]:
			for target: String in (graph[id] as Dictionary).get(dir, []):
				referenced[target] = true
				if not graph.has(target):
					print("  DANGLING  %s.%s -> '%s'" % [id, dir, target])
					dangling += 1
					continue
				var back: Array = (graph[target] as Dictionary).get(OPPOSITE[dir], [])
				if id not in back:
					print("  one-way   %s.%s -> %s (no %s back)" % [id, dir, target, OPPOSITE[dir]])
					asymmetric += 1
	var unreachable := 0
	for id: String in graph:
		if not referenced.has(id):
			print("  UNREACHABLE  %s (no edge points here)" % id)
			unreachable += 1
	print("  %d dangling, %d one-way, %d unreachable" % [dangling, asymmetric, unreachable])
