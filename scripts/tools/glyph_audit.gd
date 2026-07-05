@tool
extends EditorScript
## Editor aid for positioning controller glyphs (Script Editor: File > Run
## while the scene you care about is open).
##
## Prints every ControllerGlyph in the edited scene (node path, action,
## visibility) plus which logical pad_* actions have no glyph in the scene,
## and optionally batch-switches every glyph's editor preview to one
## controller art set so you can eyeball all placements per pad type.

## Set to "xbox" / "playstation" / "switch" / "generic" to batch-apply that
## preview set to every ControllerGlyph in the scene; leave "" to only audit.
const APPLY_PREVIEW_TYPE := ""


func _run() -> void:
	var root := get_scene()
	if root == null:
		push_warning("glyph_audit: no scene is being edited.")
		return
	var glyphs: Array[ControllerGlyph] = []
	_collect(root, glyphs)
	print("=== ControllerGlyph audit: %s (%d glyphs) ===" % [root.name, glyphs.size()])
	var covered := {}
	for glyph in glyphs:
		covered[glyph.action] = true
		print("  %-40s action=%-22s preview=%-11s always_visible=%s" % [
			root.get_path_to(glyph), glyph.action, glyph.preview_type, glyph.always_visible])
		if APPLY_PREVIEW_TYPE != "":
			glyph.preview_type = APPLY_PREVIEW_TYPE
	if APPLY_PREVIEW_TYPE != "":
		print("  -> applied preview_type=%s to all glyphs" % APPLY_PREVIEW_TYPE)
	var missing := PackedStringArray()
	for logical: StringName in GlyphDB.default_map():
		if not covered.has(logical):
			missing.append(String(logical))
	if missing.is_empty():
		print("  All rebindable actions have a glyph in this scene.")
	else:
		print("  No glyph in this scene for: %s" % ", ".join(missing))
	print("  (Actions may be intentionally unglyphed here — this is a checklist, not an error.)")


func _collect(node: Node, out: Array[ControllerGlyph]) -> void:
	if node is ControllerGlyph:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)
