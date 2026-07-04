class_name MinimizeChip
extends Button

## Bottom-left restore chip shown while a card-selection overlay is
## minimized ("View Board"): the pending prompt's title + card count.
## Pressing it (the built-in `pressed` signal) restores the overlay.
## The board stays fully interactive behind it — hover previews,
## right-click zoom and the discard/monster-deck viewers all work.


func _ready() -> void:
	visible = false
	z_index = 105 # above the passive viewers (z 100) so it stays clickable
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	add_theme_font_size_override("font_size", 16)


func show_chip(title: String, count: int, is_mobile: bool) -> void:
	if count > 0:
		text = tr("STR_GB_MINIMIZED_CHIP_FMT").replace("{TITLE}", title).replace("{N}", str(count))
	else:
		text = tr("STR_GB_MINIMIZED_CHIP_NO_COUNT_FMT").replace("{TITLE}", title)
	# Anchors sit on the viewport's bottom-left corner; size the rect
	# explicitly from the text (44px min height on mobile for a touch target,
	# 140px bottom clearance for the mobile action bar — same as the choice panel).
	var chip_size := get_combined_minimum_size() + Vector2(24.0, 8.0)
	if is_mobile:
		chip_size.y = maxf(chip_size.y, 44.0)
	offset_left = 10.0
	offset_right = 10.0 + chip_size.x
	offset_bottom = -140.0 if is_mobile else -12.0
	offset_top = offset_bottom - chip_size.y
	visible = true


func hide_chip() -> void:
	visible = false
