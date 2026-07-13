extends Control

## Boot scene for the headful online smoke pilot. This node is REPLACED by the
## GameBoard scene change when the match starts, so all it does is park the
## persistent OnlinePilot driver under /root and get out of the way.
##
## Run (after ServerMain):
##   godot --path . tests/harness/OnlinePilot.tscn -- --create --port=12191
##   godot --path . tests/harness/OnlinePilot.tscn -- --join --port=12191

const ONLINE_PILOT := preload("res://tests/harness/online_pilot.gd")


func _ready() -> void:
	var pilot := ONLINE_PILOT.new()
	pilot.name = "OnlinePilot"
	get_tree().root.add_child.call_deferred(pilot)
