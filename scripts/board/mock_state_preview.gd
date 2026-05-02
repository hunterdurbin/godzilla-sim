@tool
class_name MockStatePreview
extends Node

## Drop this Node under (or anywhere descended from) a PlayerBoard at
## edit time and it will populate the board's labels and count badges
## with placeholder values, so the editor preview shows realistic
## state instead of zeros.
##
## Pure edit-time behavior — does NOTHING at runtime. The runtime
## sync_to_state pipeline takes over the moment the game starts;
## these inspector values exist only to make the WYSIWYG preview
## meaningful.
##
## Designer can:
##   - Tweak the mock values in the inspector to verify large numbers
##     fit the layout.
##   - Delete this node entirely if they want a blank preview.
##   - Inherit a variant scene and override `enabled = false` to
##     suppress the preview without removing the node.

@export var enabled: bool = true:
	set(value):
		enabled = value
		if Engine.is_editor_hint():
			_apply()

@export_group("Player state")
@export var mock_rage: int = 5:
	set(value): mock_rage = value; _refresh_in_editor()
@export var mock_threat_bonus: int = 25000:
	set(value): mock_threat_bonus = value; _refresh_in_editor()
@export var mock_total_threat: int = 30000:
	set(value): mock_total_threat = value; _refresh_in_editor()
@export var mock_cp: int = 12000:
	set(value): mock_cp = value; _refresh_in_editor()

@export_group("Pile counts")
@export var mock_deck_size: int = 35:
	set(value): mock_deck_size = value; _refresh_in_editor()
@export var mock_discard_size: int = 8:
	set(value): mock_discard_size = value; _refresh_in_editor()
@export var mock_monster_deck_size: int = 4:
	set(value): mock_monster_deck_size = value; _refresh_in_editor()


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	# Defer one frame so the parent PlayerBoard's @export Label fields
	# have been populated by the scene loader.
	call_deferred("_apply")


func _refresh_in_editor() -> void:
	# Setter shortcut: re-apply when the designer drags an inspector slider.
	if Engine.is_editor_hint():
		call_deferred("_apply")


func _apply() -> void:
	if not Engine.is_editor_hint():
		return
	var pb := _find_player_board_ancestor()
	if pb == null:
		return
	if not enabled:
		return
	_set_label(pb, "rage_label", str(mock_rage))
	_set_label(pb, "rage_threat_label", "(+%d)" % mock_threat_bonus)
	_set_label(pb, "threat_label", str(mock_total_threat))
	_set_label(pb, "cp_label", str(mock_cp))
	_set_count_badge(pb, "deck_count_badge", mock_deck_size)
	_set_count_badge(pb, "discard_count_badge", mock_discard_size)
	_set_count_badge(pb, "monster_deck_count_badge", mock_monster_deck_size)


## Resolve an @export Node field whether it's been auto-converted to
## a Node reference yet (runtime / scene-fully-loaded state) or still
## stored as a NodePath (edit-time before the parent's _ready ran).
func _resolve_node(pb: Node, field_name: String) -> Node:
	if not field_name in pb:
		return null
	var val = pb.get(field_name)
	if val is Node:
		return val
	if val is NodePath and not (val as NodePath).is_empty():
		return pb.get_node_or_null(val)
	return null


func _set_label(pb: Node, field_name: String, text_value: String) -> void:
	var node := _resolve_node(pb, field_name)
	if node is Label:
		(node as Label).text = text_value


func _set_count_badge(pb: Node, field_name: String, value: int) -> void:
	var node := _resolve_node(pb, field_name)
	if node is Label:
		(node as Label).text = str(value)
		(node as Label).visible = true


func _find_player_board_ancestor() -> Node:
	var n := get_parent()
	while n:
		# PlayerBoard has class_name PlayerBoard, but in @tool mode the
		# class might not be loaded; check via duck-typing on a known
		# field instead.
		if n.get_script() and "rage_label" in n and "deck_count_badge" in n:
			return n
		n = n.get_parent()
	return null
