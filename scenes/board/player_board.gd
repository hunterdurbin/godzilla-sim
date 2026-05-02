class_name PlayerBoard
extends Control

## Visual representation of one player's side of the board.
## Uses zones.svg as the background with anchor-based positioning matching the SVG layout.
## The LayoutContainer maintains the SVG's 1728:1008 aspect ratio within the available space.
## Mirroring for Player 2 flips all child anchors and the background texture.

signal zone_card_dropped(zone_index: int, card: Control)
signal deck_clicked(player_id: int)
signal discard_clicked(player_id: int)
signal monster_deck_clicked(player_id: int)
signal zone_slot_clicked(zone_number: int, player_id: int)
signal zone_slot_right_clicked(zone_number: int, player_id: int)
signal strategy_slot_clicked(strategy_index: int, player_id: int)
signal strategy_slot_right_clicked(strategy_index: int, player_id: int)
signal card_preview_requested(data: Dictionary, play_cost_modifier: int)
signal card_preview_cleared()

@export var player_id: int = 0
@export var is_mirrored: bool = false # True for player 2 (top of screen)

## Auto-bind to GameSession via tree-walk (BoardModule). When true, the
## board subscribes to its PlayerState's mutation signals and refreshes
## itself — no `sync_to_state()` push call needed from the host scene.
##
## **Default true** — consistent with the other auto-binding components
## (HandSlot, BoundLabel-derived HUD primitives, BoardSfx). Production
## `GameBoard.tscn` overrides this to false on its two PlayerBoard
## instances because `game_board.gd` explicitly drives `sync_to_state`
## with full modifier data.
@export var auto_bind: bool = true

## Callable that returns a snapshot Dictionary for a player_id. Used by
## auto-bind mode to fetch state + modifiers without coupling PlayerBoard
## to host-vs-client mode logic. Signature: `(pid: int) -> Dictionary`.
## Expected dict keys (all optional with sensible defaults):
##   state, cp_mod, threat_mod, zone_cp_mods, strategy_cp_mods,
##   zone_rank_mods, monster_cp_mod, hand_rank_mods
var snapshot_provider: Callable = Callable()

## Optional path to a sibling/external CardManager that hosts this
## player's hand. Resolved on _ready when set; assigning `hand_manager`
## directly from script still works as a fallback.
@export var hand_manager_path: NodePath

var _bound_player: PlayerState = null

@export var card_scene: PackedScene = preload("res://scenes/cards/Card.tscn")

@export_group("Layout fitting")
## When true, LayoutContainer / board_bg / gradient_overlay are
## auto-positioned every frame to maintain the playmat's aspect ratio
## (legacy behavior — used by production GameBoard.tscn for the
## zones.svg playmat).
##
## **Default false** — the template ships scene-driven: LayoutContainer
## fills its parent via editor anchors, no runtime offset stomping.
## Designer-built boards see WYSIWYG positioning out of the box.
## Production scenes that need aspect-fit override this to true on
## their PlayerBoard instances in the inspector.
@export var maintain_aspect: bool = false
## Aspect ratio of the playmat artwork (defaults to zones.svg's
## 1728:1008). Only used when maintain_aspect is true.
@export var aspect_ratio: Vector2 = Vector2(1728, 1008)
## SVG content rectangle in normalized [0..1] vertical space — defines
## what fraction of the playmat is "playable" vs empty padding. The
## non-mirrored variant is used for LOCAL seats; mirrored for OPPONENT
## seats (after _apply_mirror flips the layout).
##   x = content_top, y = content_bottom
@export var content_rect_normal: Vector2 = Vector2(0.18, 0.97)
@export var content_rect_mirrored: Vector2 = Vector2(0.03, 0.82)
@export_group("")

@export_group("Count badges")
## Font size for the deck/discard/monster-deck count labels.
@export_range(8, 32) var count_badge_font_size: int = 14
@export var count_badge_color: Color = Color.WHITE
@export var count_badge_outline_color: Color = Color(0, 0, 0, 1)
@export_range(0, 10) var count_badge_outline_size: int = 4
@export_group("")

@export_group("Info zone borders")
## When true (default), runtime draws a border around each info zone
## via the _draw_border callback. Toggle off when the designer wants
## to use their own panel styling (StyleBoxFlat on the Control, etc.).
@export var enable_info_borders: bool = true
## Border drawn around the deck / discard / monster-info Control areas.
@export var info_border_color: Color = Color(0.45, 0.45, 0.55, 0.9)
@export_range(0.0, 8.0, 0.5) var info_border_width: float = 2.0
@export_group("")

@export_group("Deck stack")
## When true (default), runtime creates card-back panels under
## DeckInfo / MonsterInfo to visualize the deck's height. Toggle off
## for variants that use a different visualization.
@export var enable_deck_stack: bool = true
## Maximum number of card-back layer panels to create. The visible
## stack height grows with deck size up to this cap.
@export_range(1, 60) var deck_stack_max_layers: int = 20
## Vertical pixel shift between successive deck-stack layers. Stack
## visually grows upward as the deck grows.
@export_range(0.0, 8.0, 0.25) var deck_stack_layer_shift: float = 1.0
@export_group("")

## Inspector-wired references to PlayerBoard's internal nodes.
## PlayerBoardTemplate.tscn ships with all of these pre-populated, so a
## designer inheriting from it gets the wiring for free. _setup_references()
## falls back to find_child by name when a slot is null — meaning a designer
## who keeps the original node names doesn't have to touch the inspector.
@export_group("Layout")
@export var layout_container: Control
@export var board_bg: TextureRect
@export var gradient_overlay: ColorRect
@export var inner_background: TextureRect  # the LayoutContainer/Background TextureRect

@export_group("Battle zones")
@export var zone1_slot: Slot
@export var zone2_slot: Slot
@export var zone3_slot: Slot
@export var zone4_slot: Slot
@export var zone5_slot: Slot
@export var zone6_slot: Slot
@export var zone7_slot: Slot
@export var zone8_slot: Slot

@export_group("Strategy slots")
@export var strategy1_slot: Slot
@export var strategy2_slot: Slot
@export var strategy3_slot: Slot

@export_group("Rage block")
@export var rage_display: Control
@export var rage_bg: Panel
@export var rage_title: Label
@export var rage_label: Label
@export var rage_threat_label: Label

@export_group("Threat block")
@export var threat_row: Container
@export var threat_title: Label
@export var threat_label: Label

@export_group("CP block")
@export var cp_display: Container
@export var cp_row: Container
@export var cp_title: Label
@export var cp_label: Label

@export_group("Info zones")
@export var deck_display: Control
@export var discard_display: Control
@export var monster_info_display: Control
## Optional editor-placed count Labels inside each info zone. When set,
## the runtime skips programmatic Label.new() construction and uses the
## designer's Label as the badge — full WYSIWYG control over font,
## color, position, etc. When null, falls back to creating one with the
## "Count badges" group's defaults.
@export var deck_count_badge: Label
@export var discard_count_badge: Label
@export var monster_deck_count_badge: Label
@export_group("")

# Runtime state — populated dynamically.
var zone_slots: Array[Slot] = []
var strategy_slots: Array[Slot] = []
var hand_manager: CardManager # Set externally by GameBoard
var monster_card: Control
var monster_card_zone: int = -1 # Zone index (0-7) where monster card is currently placed

# Card-based info display caches
var _deck_card_backs: Array[Control] = []
var _discard_card: Control = null
var _discard_empty_label: Label = null
var _discard_last_id: String = ""  # Track last shown card to avoid redundant updates
var _monster_deck_card_backs: Array[Control] = []

# Card back texture cache (shared across instances)
const _DEFAULT_CARD_BACK_PATH := "res://assets/cardBacks/default.jpeg"
static var _card_back_cache_loaded: bool = false
static var _default_card_back_tex: Texture2D = null
static var _custom_card_back_tex: Texture2D = null  # null = no custom file found


func _ready() -> void:
	clip_contents = true
	_setup_references()
	_apply_custom_playmat()
	resized.connect(_update_layout)
	_update_layout()
	# Resolve hand_manager from the inspector NodePath if set and not
	# already assigned by script.
	if hand_manager == null and not hand_manager_path.is_empty():
		var node := get_node_or_null(hand_manager_path)
		if node and node is CardManager:
			hand_manager = node
	if auto_bind:
		_try_bind_to_session()


# --- Auto-bind to GameSession (drop-in modular usage) ---

func _try_bind_to_session() -> void:
	var session := BoardModule.find_session(self)
	if session == null:
		return
	# SeatContainer ancestor wins over the inspector @export player_id.
	# Drop a PlayerBoard under LocalSeat or OpponentSeat and it auto-resolves.
	var seat := BoardModule.find_seat(self)
	if seat:
		player_id = seat.get_player_id()
		if not seat.role_changed.is_connected(_on_seat_role_changed):
			seat.role_changed.connect(_on_seat_role_changed)
	if session.is_running() or not session.client_players.is_empty():
		_bind_to_session(session)
	else:
		session.session_started.connect(func(): _bind_to_session(session), CONNECT_ONE_SHOT)


func _on_seat_role_changed(new_player_id: int) -> void:
	player_id = new_player_id
	var session := BoardModule.find_session(self)
	if session and session.is_running():
		_bind_to_session(session)


func _bind_to_session(session: GameSession) -> void:
	var p := session.get_player(player_id)
	if p == null:
		return
	if _bound_player == p:
		return
	_disconnect_bound_player()
	_bound_player = p
	p.hand_changed.connect(_on_bound_state_changed)
	p.zones_changed.connect(_on_bound_state_changed)
	p.rage_changed.connect(_on_rage_changed)
	p.monster_changed.connect(_on_bound_state_changed)
	p.discard_changed.connect(_on_bound_state_changed)
	p.deck_changed.connect(_on_bound_state_changed)
	p.strategy_zones_changed.connect(_on_bound_state_changed)
	_on_bound_state_changed()


func _on_rage_changed(_new_rage: int) -> void:
	_on_bound_state_changed()


func _disconnect_bound_player() -> void:
	if _bound_player == null:
		return
	if _bound_player.hand_changed.is_connected(_on_bound_state_changed):
		_bound_player.hand_changed.disconnect(_on_bound_state_changed)
	if _bound_player.zones_changed.is_connected(_on_bound_state_changed):
		_bound_player.zones_changed.disconnect(_on_bound_state_changed)
	if _bound_player.rage_changed.is_connected(_on_rage_changed):
		_bound_player.rage_changed.disconnect(_on_rage_changed)
	if _bound_player.monster_changed.is_connected(_on_bound_state_changed):
		_bound_player.monster_changed.disconnect(_on_bound_state_changed)
	if _bound_player.discard_changed.is_connected(_on_bound_state_changed):
		_bound_player.discard_changed.disconnect(_on_bound_state_changed)
	if _bound_player.deck_changed.is_connected(_on_bound_state_changed):
		_bound_player.deck_changed.disconnect(_on_bound_state_changed)
	if _bound_player.strategy_zones_changed.is_connected(_on_bound_state_changed):
		_bound_player.strategy_zones_changed.disconnect(_on_bound_state_changed)


func _on_bound_state_changed() -> void:
	if _bound_player == null:
		return
	if snapshot_provider.is_valid():
		var snap = snapshot_provider.call(player_id)
		if typeof(snap) == TYPE_DICTIONARY and not snap.is_empty():
			sync_to_state(
				snap.get("state", _bound_player),
				int(snap.get("cp_mod", 0)),
				int(snap.get("threat_mod", 0)),
				snap.get("zone_cp_mods", []),
				snap.get("strategy_cp_mods", []),
				snap.get("zone_rank_mods", []),
				int(snap.get("monster_cp_mod", 0)),
				snap.get("hand_rank_mods", []))
			return
	# No snapshot_provider — refresh with no modifiers (sensible default for
	# scenes that don't yet have effect-modifier rendering).
	sync_to_state(_bound_player)


func _update_layout() -> void:
	# Designer opt-out: when maintain_aspect is false the LayoutContainer /
	# board_bg / gradient_overlay use their editor-set anchors as-is.
	if not maintain_aspect:
		return
	# Crop into the zone content area of the playmat, removing empty top/
	# bottom space. content_rect_normal/mirrored are @export so designers
	# can tune the visible content band per orientation.
	var rect: Vector2 = content_rect_mirrored if is_mirrored else content_rect_normal
	var content_top: float = rect.x
	var content_bottom: float = rect.y

	var content_span := content_bottom - content_top
	var lc_height := size.y / content_span

	# Preserve aspect ratio: constrain width or height so the board never
	# stretches in either direction.
	var ar_x: float = aspect_ratio.x if aspect_ratio.x > 0.0 else 1728.0
	var ar_y: float = aspect_ratio.y if aspect_ratio.y > 0.0 else 1008.0
	var lc_width := lc_height * (ar_x / ar_y)
	var actual_width := minf(lc_width, size.x)
	var x_offset := maxf(0.0, (size.x - actual_width) / 2.0)

	# When width-constrained (tall/narrow display), recalculate height from
	# the clamped width so zones and info areas keep their aspect ratio
	# instead of stretching vertically.
	if actual_width < lc_width:
		lc_height = actual_width / (ar_x / ar_y)

	# Center the visible content area vertically within the available space.
	var visible_height := content_span * lc_height
	var y_offset := (size.y - visible_height) / 2.0

	if layout_container == null:
		# _update_layout can fire from `resized` before _setup_references finishes
		# resolving exports; bail out — _setup_references calls _update_layout again.
		return
	layout_container.offset_left = x_offset
	layout_container.offset_top = y_offset - content_top * lc_height
	layout_container.offset_right = x_offset + actual_width
	layout_container.offset_bottom = layout_container.offset_top + lc_height

	# Constrain playmat background and overlay to match the LayoutContainer width
	if board_bg:
		board_bg.anchor_left = 0.0
		board_bg.anchor_right = 0.0
		board_bg.anchor_top = 0.0
		board_bg.anchor_bottom = 1.0
		board_bg.offset_left = x_offset
		board_bg.offset_right = x_offset + actual_width

	if gradient_overlay:
		gradient_overlay.anchor_left = 0.0
		gradient_overlay.anchor_right = 0.0
		gradient_overlay.anchor_top = 0.0
		gradient_overlay.anchor_bottom = 1.0
		gradient_overlay.offset_left = x_offset
		gradient_overlay.offset_right = x_offset + actual_width

	# On mobile, bump label font sizes so they're readable on smaller boards.
	# The LayoutContainer scales via anchors but font sizes are fixed pixels,
	# so we set explicit sizes that work at phone scale.
	if GameSettings.use_mobile_layout:
		_apply_mobile_labels()


var _mobile_labels_applied := false
var _target_value_font_size: int = 14

func _apply_mobile_labels() -> void:
	if _mobile_labels_applied:
		return
	_mobile_labels_applied = true
	if threat_title:
		threat_title.text = tr("STR_PB_THREAT_SHORT")  # Abbreviate to save horizontal space
	if cp_title:
		cp_title.text = tr("STR_PB_CP")
	if cp_label:
		cp_label.custom_minimum_size.x = 0.0
		cp_label.clip_text = true
		cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		cp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cp_label.resized.connect(func(): _apply_autofit(cp_label, 8))
	if threat_label:
		threat_label.custom_minimum_size.x = 0.0
		threat_label.clip_text = true
		threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		threat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		threat_label.resized.connect(func(): _apply_autofit(threat_label, 8))
	# Apply default (balanced) font sizes
	apply_mobile_label_scale(1.0)


## Update mobile label font sizes based on board scale.
## scale = 1.0 for balanced/enlarged, ~0.6 for shrunk board.
func apply_mobile_label_scale(label_scale: float) -> void:
	var title_size := maxi(10, int(14 * label_scale))
	var value_size := maxi(12, int(18 * label_scale))
	var rage_size := maxi(14, int(28 * label_scale))
	var rage_threat_size := maxi(10, int(18 * label_scale))
	if cp_title:
		cp_title.add_theme_font_size_override("font_size", title_size)
	if threat_title:
		threat_title.add_theme_font_size_override("font_size", title_size)
	_target_value_font_size = value_size
	if cp_label:
		cp_label.add_theme_font_size_override("font_size", value_size)
	if threat_label:
		threat_label.add_theme_font_size_override("font_size", value_size)
	if rage_title:
		rage_title.add_theme_font_size_override("font_size", title_size)
	if rage_label:
		rage_label.add_theme_font_size_override("font_size", rage_size)
	if rage_threat_label:
		rage_threat_label.add_theme_font_size_override("font_size", rage_threat_size)


func _setup_references() -> void:
	_resolve_export_fallbacks()

	# Mirror for player 2: flip all child anchors and background
	if is_mirrored:
		_apply_mirror()

	# Determine if this is the local player's board
	var local_id := NetworkManager.get_local_player_id() if NetworkManager.is_multiplayer() else (NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0)
	var is_local := player_id == local_id

	if rage_display:
		if is_local:
			# Local player: move RageTitle to the bottom of the VBox
			if rage_title:
				rage_display.move_child(rage_title, rage_display.get_child_count() - 1)
		else:
			# Opponent: move ThreatRow to bottom (closest to center divider)
			if threat_row:
				rage_display.move_child(threat_row, rage_display.get_child_count() - 1)

	if cp_display and not is_local and cp_display is BoxContainer:
		# Opponent: align CPRow to bottom (closest to center divider)
		(cp_display as BoxContainer).alignment = BoxContainer.ALIGNMENT_END

	# Zone slots (use @export references; fallback handled in _resolve_export_fallbacks)
	zone_slots.resize(8)
	var zone_exports: Array = [
		zone1_slot, zone2_slot, zone3_slot, zone4_slot,
		zone5_slot, zone6_slot, zone7_slot, zone8_slot,
	]
	for i in range(8):
		var slot: Slot = zone_exports[i]
		if slot:
			slot.zone_number = i + 1
			slot.slot_type = "battle_zone"
			slot.player_id = player_id
			slot.slot_clicked.connect(_on_zone_slot_clicked)
			slot.slot_right_clicked.connect(_on_zone_slot_right_clicked)
			slot.slot_hover_preview.connect(_on_slot_hover_preview)
			slot.slot_hover_preview_cleared.connect(_on_slot_hover_cleared)
			zone_slots[i] = slot

	# Strategy slots (landscape orientation)
	var strategy_exports: Array = [strategy1_slot, strategy2_slot, strategy3_slot]
	for i in range(strategy_exports.size()):
		var slot: Slot = strategy_exports[i]
		if slot:
			slot.zone_number = 0
			slot.slot_type = "strategy_zone"
			slot.player_id = player_id
			slot.landscape = true
			slot.slot_clicked.connect(_on_strategy_slot_clicked.bind(i))
			slot.slot_right_clicked.connect(_on_strategy_slot_right_clicked.bind(i))
			slot.slot_hover_preview.connect(_on_slot_hover_preview)
			slot.slot_hover_preview_cleared.connect(_on_slot_hover_cleared)
			strategy_slots.append(slot)

	_style_rage_bg()

	# Deck: dynamic stack of face-down cards (height reflects card count) + hover count badge
	if deck_display:
		if enable_deck_stack:
			_create_deck_stack(deck_display, _deck_card_backs)
		# Editor-placed badge wins; fall back to programmatic construction.
		if deck_count_badge == null:
			deck_count_badge = _create_count_badge()
			deck_display.add_child(deck_count_badge)
		deck_display.mouse_entered.connect(deck_count_badge.show)
		deck_display.mouse_exited.connect(deck_count_badge.hide)
		deck_display.mouse_filter = Control.MOUSE_FILTER_STOP
		deck_display.gui_input.connect(_on_deck_gui_input)

	# Discard: face-up top card + empty placeholder + hover count badge
	if discard_display:
		_discard_card = _create_card({})
		_discard_empty_label = PlayerBoardHelpers.setup_discard_zone(
			discard_display, _discard_card, tr("STR_PB_DISCARD")
		)
		if discard_count_badge == null:
			discard_count_badge = _create_count_badge()
			discard_display.add_child(discard_count_badge)

	# Monster deck: dynamic stack of face-down cards + hover count badge + player label
	if monster_info_display:
		if enable_deck_stack:
			_create_deck_stack(monster_info_display, _monster_deck_card_backs)
		if monster_deck_count_badge == null:
			monster_deck_count_badge = _create_count_badge()
			monster_info_display.add_child(monster_deck_count_badge)
		monster_info_display.mouse_entered.connect(monster_deck_count_badge.show)
		monster_info_display.mouse_exited.connect(monster_deck_count_badge.hide)

	# Make discard area clickable + hover preview/badge
	if discard_display:
		discard_display.mouse_filter = Control.MOUSE_FILTER_STOP
		discard_display.gui_input.connect(_on_discard_gui_input)
		discard_display.mouse_entered.connect(_on_discard_hover_started)
		discard_display.mouse_exited.connect(_on_discard_hover_ended)

	# Make monster info area clickable
	if monster_info_display:
		monster_info_display.mouse_filter = Control.MOUSE_FILTER_STOP
		monster_info_display.gui_input.connect(_on_monster_info_gui_input)

	# Add borders to info areas (designer can disable to use their own styling)
	if enable_info_borders:
		for area in [deck_display, discard_display, monster_info_display]:
			if area:
				_add_border(area)


## Fall back to find_child by name for any @export slot the inherited
## scene didn't populate. Lets a designer who keeps the original node
## names skip wiring everything in the inspector while still letting a
## restructured / renamed scene wire its own references explicitly.
func _resolve_export_fallbacks() -> void:
	if layout_container == null: layout_container = find_child("LayoutContainer", true, false) as Control
	if board_bg == null: board_bg = find_child("BoardBg", true, false) as TextureRect
	if gradient_overlay == null: gradient_overlay = find_child("GradientOverlay", true, false) as ColorRect
	if inner_background == null and layout_container:
		inner_background = layout_container.find_child("Background", false, false) as TextureRect
	if zone1_slot == null: zone1_slot = find_child("Zone1", true, false) as Slot
	if zone2_slot == null: zone2_slot = find_child("Zone2", true, false) as Slot
	if zone3_slot == null: zone3_slot = find_child("Zone3", true, false) as Slot
	if zone4_slot == null: zone4_slot = find_child("Zone4", true, false) as Slot
	if zone5_slot == null: zone5_slot = find_child("Zone5", true, false) as Slot
	if zone6_slot == null: zone6_slot = find_child("Zone6", true, false) as Slot
	if zone7_slot == null: zone7_slot = find_child("Zone7", true, false) as Slot
	if zone8_slot == null: zone8_slot = find_child("Zone8", true, false) as Slot
	if strategy1_slot == null: strategy1_slot = find_child("Strategy1", true, false) as Slot
	if strategy2_slot == null: strategy2_slot = find_child("Strategy2", true, false) as Slot
	if strategy3_slot == null: strategy3_slot = find_child("Strategy3", true, false) as Slot
	if rage_display == null: rage_display = find_child("RageDisplay", true, false) as Control
	if rage_bg == null: rage_bg = find_child("RageBg", true, false) as Panel
	if rage_title == null: rage_title = find_child("RageTitle", true, false) as Label
	if rage_label == null: rage_label = find_child("RageLabel", true, false) as Label
	if rage_threat_label == null: rage_threat_label = find_child("RageThreatLabel", true, false) as Label
	if threat_row == null: threat_row = find_child("ThreatRow", true, false) as Container
	if threat_title == null: threat_title = find_child("ThreatTitle", true, false) as Label
	if threat_label == null: threat_label = find_child("ThreatLabel", true, false) as Label
	if cp_display == null: cp_display = find_child("CPDisplay", true, false) as Container
	if cp_row == null: cp_row = find_child("CPRow", true, false) as Container
	if cp_title == null: cp_title = find_child("CPTitle", true, false) as Label
	if cp_label == null: cp_label = find_child("CPLabel", true, false) as Label
	if deck_display == null: deck_display = find_child("DeckInfo", true, false) as Control
	if discard_display == null: discard_display = find_child("DiscardInfo", true, false) as Control
	if monster_info_display == null: monster_info_display = find_child("MonsterInfo", true, false) as Control


## Case-insensitive file search for custom assets (iOS filesystem is case-sensitive).
func _find_custom_file(dir_path: String, base_name: String) -> String:
	var da := DirAccess.open(dir_path)
	if da == null:
		return ""
	var prefix := base_name.to_lower() + "."
	da.list_dir_begin()
	var file_name := da.get_next()
	while not file_name.is_empty():
		if not da.current_is_dir() and file_name.to_lower().begins_with(prefix):
			return dir_path.path_join(file_name)
		file_name = da.get_next()
	return ""


func _apply_custom_playmat() -> void:
	if not GameSettings.custom_playmat_enabled:
		return
	var local_id := NetworkManager.get_local_player_id() if NetworkManager.is_multiplayer() else (NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0)
	if player_id != local_id and not GameSettings.custom_playmat_opponent:
		return
	var dir_path := GameSettings.get_custom_base_path().path_join("playmat")
	var image_path := _find_custom_file(dir_path, "default")
	if not image_path.is_empty():
		var image := Image.load_from_file(image_path)
		if image:
			var tex := ImageTexture.create_from_image(image)
			if board_bg:
				board_bg.texture = tex


## Apply a gradient tint to the board background based on the rank 1 monster's colors.
## Call once during initial board setup.
func apply_monster_gradient(monster_data: Dictionary) -> void:
	if GameSettings.color_overlay_mode == 0:
		return
	var local_id := NetworkManager.get_local_player_id() if NetworkManager.is_multiplayer() else (NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0)
	var is_self := player_id == local_id
	if is_self and GameSettings.color_overlay_mode == 2:
		return
	if not is_self and GameSettings.color_overlay_mode == 1:
		return
	var overlay := gradient_overlay
	if not overlay:
		return
	var colors: Array = monster_data.get("colors", [])
	if colors.is_empty():
		return
	var gradient := GradientTexture2D.new()
	var grad := Gradient.new()
	if colors.size() == 1:
		var c: Color = CardEnums.color_to_godot_color(colors[0])
		c.a = 0.15
		grad.colors = PackedColorArray([c, Color(c.r, c.g, c.b, 0.0)])
	else:
		var c1: Color = CardEnums.color_to_godot_color(colors[0])
		var c2: Color = CardEnums.color_to_godot_color(colors[1])
		c1.a = 0.15
		c2.a = 0.15
		grad.colors = PackedColorArray([c1, c2])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.gradient = grad
	gradient.width = 256
	gradient.height = 256
	gradient.fill_from = Vector2(0.0, 0.0)
	gradient.fill_to = Vector2(1.0, 1.0)
	# Use a TextureRect instead of ColorRect for gradient support
	var tex_rect := TextureRect.new()
	tex_rect.texture = gradient
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(tex_rect)
	overlay.color = Color(0, 0, 0, 0) # Keep parent transparent


## Sync the entire board display to match a PlayerState
func sync_to_state(player_state: PlayerState, cp_modifier: int = 0, threat_modifier: int = 0, zone_cp_mods: Array = [], strategy_cp_mods: Array = [], zone_rank_mods: Array = [], monster_cp_mod: int = 0, hand_rank_mods: Array = []) -> void:
	_sync_zones(player_state, zone_cp_mods, zone_rank_mods)
	_sync_strategy_zones(player_state, strategy_cp_mods)
	_sync_monster(player_state, threat_modifier, monster_cp_mod)
	_sync_hand(player_state)
	_sync_hand_badges(player_state, hand_rank_mods)
	_sync_info(player_state, cp_modifier, threat_modifier)


func _sync_zones(state: PlayerState, zone_cp_mods: Array = [], zone_rank_mods: Array = []) -> void:
	for i in range(mini(zone_slots.size(), 8)):
		var slot := zone_slots[i]
		if not slot:
			continue

		# Skip the monster's zone — monster card is managed by _sync_monster
		# Clamp to zone 8 (index 7) so victory invasion still shows monster
		if mini(state.monster_zone - 1, zone_slots.size() - 1) == i:
			slot.set_monster_marker(true)
			# Remove any battle card visual so the monster card can be placed by _sync_monster
			if slot.has_card() and slot.get_card() != monster_card:
				slot.remove_card(true)
			continue

		slot.set_monster_marker(false)
		var zone_data: Dictionary = state.get_zone_top_card(i)
		var stack_size: int = state.get_zone_stack(i).size()
		var cp_mod: int = zone_cp_mods[i] if i < zone_cp_mods.size() else 0
		var rank_mod: int = zone_rank_mods[i] if i < zone_rank_mods.size() else 0

		# Update card in slot
		if zone_data.is_empty() and slot.has_card() and slot.get_card() != monster_card:
			slot.remove_card(true)
		elif not zone_data.is_empty() and not slot.has_card():
			var card := _create_card(zone_data)
			card.drag_enabled = false
			slot.place_card(card, false)
			if stack_size > 1:
				_add_stack_badge(card, stack_size)
			_update_modifier_badge(card, cp_mod)
			_update_rank_modifier_badge(card, rank_mod)
		elif not zone_data.is_empty() and slot.has_card():
			var card := slot.get_card()
			if card.has_method("set_card_data_dict"):
				card.set_card_data_dict(zone_data)
			_update_stack_badge(card, stack_size)
			_update_modifier_badge(card, cp_mod)
			_update_rank_modifier_badge(card, rank_mod)


func _sync_strategy_zones(state: PlayerState, strategy_cp_mods: Array = []) -> void:
	var zone_count: int = state.strategy_zones.size()

	# Show/hide and reposition slots when 3rd strategy zone is added
	if zone_count >= 3 and strategy_slots.size() >= 3 and not strategy_slots[2].visible:
		_redistribute_strategy_slots(zone_count)

	for i in range(mini(strategy_slots.size(), zone_count)):
		var slot := strategy_slots[i]
		if not slot:
			continue
		var sz_data: Dictionary = state.strategy_zones[i]
		var cp_mod: int = strategy_cp_mods[i] if i < strategy_cp_mods.size() else 0

		if sz_data.is_empty() and slot.has_card():
			slot.remove_card(true)
		elif not sz_data.is_empty() and not slot.has_card():
			var card := _create_card(sz_data)
			card.drag_enabled = false
			slot.place_card(card, false)
			_update_strategy_modifier_badge(card, cp_mod)
		elif not sz_data.is_empty() and slot.has_card():
			_update_strategy_modifier_badge(slot.get_card(), cp_mod)


func _redistribute_strategy_slots(count: int) -> void:
	if count < 3 or strategy_slots.size() < 3:
		return
	# Redistribute 3 strategy slots within the original 2-slot vertical space
	var top_start := 0.204
	var bottom_end := 0.5969
	var gap := 0.01
	var zone_height := (bottom_end - top_start - gap * (count - 1)) / count
	for i in range(count):
		var slot := strategy_slots[i]
		var a_top := top_start + i * (zone_height + gap)
		var a_bottom := a_top + zone_height
		if is_mirrored:
			var flipped_top := 1.0 - a_bottom
			var flipped_bottom := 1.0 - a_top
			a_top = flipped_top
			a_bottom = flipped_bottom
		slot.custom_minimum_size = Vector2.ZERO
		# Set larger anchor first to avoid clamping
		slot.anchor_bottom = a_bottom
		slot.anchor_top = a_top
		slot.offset_top = 0
		slot.offset_bottom = 0
		slot.visible = true


func _restore_strategy_slot_anchors() -> void:
	# Original anchor values from PlayerBoard.tscn (non-mirrored)
	var originals := [
		{"top": 0.204, "bottom": 0.3908},
		{"top": 0.4103, "bottom": 0.5969},
	]
	for i in range(mini(2, strategy_slots.size())):
		var slot := strategy_slots[i]
		var a_top: float = originals[i]["top"]
		var a_bottom: float = originals[i]["bottom"]
		if is_mirrored:
			var flipped_top := 1.0 - a_bottom
			var flipped_bottom := 1.0 - a_top
			a_top = flipped_top
			a_bottom = flipped_bottom
		slot.anchor_bottom = a_bottom
		slot.anchor_top = a_top
		slot.offset_top = 0
		slot.offset_bottom = 0


func _sync_monster(state: PlayerState, threat_mod: int = 0, cp_mod: int = 0) -> void:
	var m: Dictionary = state.current_monster
	var target_zone: int = mini(state.monster_zone - 1, zone_slots.size() - 1) # 0-indexed, clamped to zone 8

	if not m.is_empty():
		# Create card if it doesn't exist yet
		if not monster_card:
			monster_card = _create_card(m)
			monster_card.drag_enabled = false
		elif monster_card.has_method("set_card_data_dict"):
			monster_card.set_card_data_dict(m)

		# Move to the correct zone slot if zone changed
		if target_zone != monster_card_zone:
			# Remove from old slot
			if monster_card_zone >= 0 and monster_card_zone < zone_slots.size():
				var old_slot := zone_slots[monster_card_zone]
				if old_slot and old_slot.has_card() and old_slot.get_card() == monster_card:
					old_slot.remove_card(false)
			# Place in new slot
			if target_zone >= 0 and target_zone < zone_slots.size():
				var new_slot := zone_slots[target_zone]
				if new_slot:
					new_slot.place_card(monster_card, false)
			monster_card_zone = target_zone

		_update_threat_modifier_badge(monster_card, threat_mod)
		_update_monster_cp_badge(monster_card, cp_mod)

	if rage_label:
		rage_label.text = "%d" % state.rage
	if rage_threat_label:
		var threat_bonus: int = state.rage * 5000
		rage_threat_label.text = "(+%s)" % _format_number(threat_bonus)


func _sync_hand(state: PlayerState) -> void:
	if not hand_manager:
		return

	var current_cards := hand_manager.get_cards()

	# Same set of cards (ignoring visual order) — nothing to do
	if _hand_set_matches(current_cards, state.hand):
		return

	# Diff: match visual cards against state cards by ID (handling duplicates)
	var state_pool: Array[Dictionary] = state.hand.duplicate()
	var cards_to_remove: Array[Control] = []

	for card in current_cards:
		var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
		var found_idx := -1
		for j in range(state_pool.size()):
			if state_pool[j].get("id", "") == card_id:
				found_idx = j
				break
		if found_idx >= 0:
			state_pool.remove_at(found_idx)
		else:
			cards_to_remove.append(card)

	# Suppress intermediate rearrangements
	var was_auto := hand_manager.auto_arrange
	hand_manager.auto_arrange = false

	for card in cards_to_remove:
		hand_manager.remove_card(card, false)
		card.queue_free()

	# state_pool now contains only newly drawn cards
	var new_card_count := state_pool.size()
	for card_data in state_pool:
		var card := _create_card(card_data)
		if is_mirrored:
			card.invert_hover = true
		hand_manager.add_card(card, false)

	# Pre-position new cards at their target slots so they appear at the end
	# instead of flying in from (0,0)
	if new_card_count > 0:
		var total := hand_manager.get_card_count()
		var positions := hand_manager._compute_slot_positions(total)
		var cards := hand_manager.get_cards()
		for k in range(new_card_count):
			var idx := total - new_card_count + k
			if idx >= 0 and idx < positions.size():
				cards[idx].position = positions[idx]

	hand_manager.auto_arrange = was_auto
	hand_manager.arrange_cards(true)


## Apply per-card play-cost modifier badges to the hand. Runs unconditionally
## (badges can change even when the hand-set hasn't, e.g. when a strategy is
## played that buffs/nerfs cost). Face-down hands skip the badge to avoid
## leaking info to the opponent.
func _sync_hand_badges(state: PlayerState, hand_rank_mods: Array) -> void:
	if not hand_manager:
		return
	var visual_cards := hand_manager.get_cards()
	# Match visual cards to state.hand by ID (handles duplicate IDs by consuming
	# from a pool, mirroring _sync_hand's pairing). Visual order may differ from
	# state order due to user reordering; matching by ID keeps badges correct.
	var pool: Array = []
	for i in range(state.hand.size()):
		var mod: int = hand_rank_mods[i] if i < hand_rank_mods.size() else 0
		pool.append({"id": state.hand[i].get("id", ""), "mod": mod})
	for card in visual_cards:
		if not card.has_method("set_play_cost_modifier"):
			continue
		if "is_face_down" in card and card.is_face_down:
			card.set_play_cost_modifier(0)
			continue
		var card_id: String = card.card_data.get("id", "") if "card_data" in card else ""
		var matched_mod := 0
		for j in range(pool.size()):
			if pool[j]["id"] == card_id:
				matched_mod = pool[j]["mod"]
				pool.remove_at(j)
				break
		card.set_play_cost_modifier(matched_mod)


func _hand_set_matches(visual_cards: Array[Control], state_hand: Array) -> bool:
	if visual_cards.size() != state_hand.size():
		return false
	var visual_counts := {}
	for card in visual_cards:
		var id: String = card.card_data.get("id", "") if "card_data" in card else ""
		visual_counts[id] = visual_counts.get(id, 0) + 1
	var state_counts := {}
	for cd in state_hand:
		var id: String = cd.get("id", "")
		state_counts[id] = state_counts.get(id, 0) + 1
	return visual_counts == state_counts


func _sync_info(state: PlayerState, cp_modifier: int = 0, threat_modifier: int = 0) -> void:
	# Deck: show/hide card backs proportional to remaining cards
	var deck_size: int = state.main_deck.size()
	if deck_count_badge:
		deck_count_badge.text = "%d" % deck_size
	var visible_count: int = mini(deck_size, _deck_card_backs.size())
	for i in range(_deck_card_backs.size()):
		_deck_card_backs[i].visible = i < visible_count

	# Discard: show top card face-up, update count badge
	var discard_size: int = state.discard_pile.size()
	if discard_count_badge:
		discard_count_badge.text = "%d" % discard_size
	if discard_size > 0:
		var top_card: Dictionary = state.discard_pile.back()
		var top_id: String = top_card.get("id", "")
		if _discard_card:
			if top_id != _discard_last_id:
				_discard_card.set_card_data_dict(top_card)
				_discard_last_id = top_id
			_discard_card.visible = true
		if _discard_empty_label:
			_discard_empty_label.visible = false
	else:
		if _discard_card:
			_discard_card.visible = false
			_discard_last_id = ""
		if _discard_empty_label:
			_discard_empty_label.visible = true

	# Monster deck: show/hide card backs proportional to remaining cards
	var monster_deck_size: int = state.monster_deck.size()
	if monster_deck_count_badge:
		monster_deck_count_badge.text = "%d" % monster_deck_size
	var monster_visible: int = mini(monster_deck_size, _monster_deck_card_backs.size())
	for i in range(_monster_deck_card_backs.size()):
		_monster_deck_card_backs[i].visible = i < monster_visible

	if cp_label:
		var total_cp: int = state.get_total_counter_power() + cp_modifier
		_set_label_autofit(cp_label, _format_number(total_cp))
	if threat_label:
		var total_threat: int = state.get_threat_level() + threat_modifier
		_set_label_autofit(threat_label, _format_number(total_threat))


func set_hand_face_down(face_down: bool) -> void:
	if not hand_manager:
		return
	for card in hand_manager.get_cards():
		if card.has_method("set_face_down"):
			card.set_face_down(face_down)
		if face_down and card.has_method("set_play_cost_modifier"):
			card.set_play_cost_modifier(0)


func highlight_valid_zones(valid_zone_indices: Array[int]) -> void:
	for i in range(zone_slots.size()):
		if zone_slots[i]:
			zone_slots[i].set_highlighted(i in valid_zone_indices)


func highlight_strategy_zones() -> void:
	for slot in strategy_slots:
		if slot and not slot.has_card():
			slot.set_highlighted(true)


func _style_rage_bg() -> void:
	if rage_bg:
		PlayerBoardHelpers.style_rage_bg(rage_bg)


func highlight_rage_zone(highlight: bool) -> void:
	if rage_display:
		if highlight:
			rage_display.modulate = Color(1.2, 1.5, 1.2, 1.0)
		else:
			rage_display.modulate = Color.WHITE


func highlight_discard_zone(highlight: bool) -> void:
	if discard_display:
		if highlight:
			discard_display.modulate = Color(1.2, 1.5, 1.2, 1.0)
		else:
			discard_display.modulate = Color.WHITE


func clear_highlights() -> void:
	for slot in zone_slots:
		if slot:
			slot.set_highlighted(false)
	for slot in strategy_slots:
		if slot:
			slot.set_highlighted(false)
	highlight_rage_zone(false)
	highlight_discard_zone(false)


## Clear all visual state for a fresh game (called during rematch).
func reset_visuals() -> void:
	# Remove all cards from zone slots
	for slot in zone_slots:
		if slot:
			if slot.has_card() and slot.get_card() != monster_card:
				slot.remove_card(true)
			slot.set_highlighted(false)
			slot.set_monster_marker(false)

	# Remove monster card
	if monster_card:
		# Remove from its slot first
		if monster_card_zone >= 0 and monster_card_zone < zone_slots.size():
			var slot := zone_slots[monster_card_zone]
			if slot and slot.has_card() and slot.get_card() == monster_card:
				slot.remove_card(false)
		monster_card.queue_free()
		monster_card = null
	monster_card_zone = -1

	# Remove all cards from strategy slots
	for slot in strategy_slots:
		if slot:
			if slot.has_card():
				slot.remove_card(true)
			slot.set_highlighted(false)

	# Reset strategy slot layout if 3rd zone was added (EBP03-013)
	if strategy_slots.size() >= 3:
		strategy_slots[2].visible = false
		_restore_strategy_slot_anchors()

	# Clear gradient overlay children (TextureRects created by apply_monster_gradient)
	if gradient_overlay:
		for child in gradient_overlay.get_children():
			child.queue_free()
		gradient_overlay.color = Color(0, 0, 0, 0)

	# Reset discard card display
	if _discard_card:
		_discard_card.visible = false
		_discard_last_id = ""
	if _discard_empty_label:
		_discard_empty_label.visible = true

	highlight_rage_zone(false)
	highlight_discard_zone(false)


func _apply_mirror() -> void:
	if inner_background:
		inner_background.flip_h = true
		inner_background.flip_v = true
	if board_bg:
		board_bg.flip_h = true
		board_bg.flip_v = true
	if layout_container:
		for child in layout_container.get_children():
			if child is TextureRect:
				continue
			if child is Control:
				_flip_node_anchors(child)


func _flip_node_anchors(node: Control) -> void:
	var l := node.anchor_left
	var t := node.anchor_top
	var r := node.anchor_right
	var b := node.anchor_bottom
	# Set the larger values first to avoid clamping
	node.anchor_right = 1.0 - l
	node.anchor_bottom = 1.0 - t
	node.anchor_left = 1.0 - r
	node.anchor_top = 1.0 - b
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0


func toggle_mirrored() -> void:
	is_mirrored = !is_mirrored
	# Flip all child anchors (flipping twice = identity, so this toggles)
	if layout_container:
		for child in layout_container.get_children():
			if child is TextureRect:
				continue
			if child is Control:
				_flip_node_anchors(child)
	if inner_background:
		inner_background.flip_h = is_mirrored
		inner_background.flip_v = is_mirrored
	if board_bg:
		board_bg.flip_h = is_mirrored
		board_bg.flip_v = is_mirrored
	# Recalculate LayoutContainer crop for the new mirrored state
	_update_layout()


func _on_deck_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		deck_clicked.emit(player_id)


func _on_discard_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		discard_clicked.emit(player_id)


func _on_monster_info_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		monster_deck_clicked.emit(player_id)


func _on_zone_slot_clicked(zone_num: int, pid: int) -> void:
	zone_slot_clicked.emit(zone_num, pid)


func _on_zone_slot_right_clicked(zone_num: int, pid: int) -> void:
	zone_slot_right_clicked.emit(zone_num, pid)


func _on_strategy_slot_clicked(_zone_num: int, _pid: int, strategy_idx: int) -> void:
	strategy_slot_clicked.emit(strategy_idx, player_id)


func _on_strategy_slot_right_clicked(_zone_num: int, _pid: int, strategy_idx: int) -> void:
	strategy_slot_right_clicked.emit(strategy_idx, player_id)


func _create_card(data: Dictionary) -> Control:
	var card: Control = card_scene.instantiate()
	card.owner_player_id = player_id
	if card.has_method("set_card_data_dict"):
		card.set_card_data_dict(data)
	if card.has_signal("card_hover_started"):
		card.card_hover_started.connect(_on_card_hover_started)
	if card.has_signal("card_hover_ended"):
		card.card_hover_ended.connect(_on_card_hover_ended)
	return card


func _on_slot_hover_preview(data: Dictionary) -> void:
	card_preview_requested.emit(data, 0)


func _on_slot_hover_cleared() -> void:
	card_preview_cleared.emit()


func _on_card_hover_started(card_ctrl: Control) -> void:
	if "card_data" in card_ctrl and not card_ctrl.card_data.is_empty():
		var mod: int = card_ctrl.get_play_cost_modifier() if card_ctrl.has_method("get_play_cost_modifier") else 0
		card_preview_requested.emit(card_ctrl.card_data, mod)


func _on_card_hover_ended(_card_ctrl: Control) -> void:
	card_preview_cleared.emit()


func _add_stack_badge(card: Control, count: int) -> void:
	if count <= 1:
		return
	var badge := Label.new()
	badge.name = "StackBadge"
	badge.text = "x%d" % count
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color.YELLOW)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 3)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -40
	badge.offset_right = -4
	badge.offset_top = 4
	card.add_child(badge)


func _update_stack_badge(card: Control, count: int) -> void:
	var badge := card.get_node_or_null("StackBadge")
	if count <= 1:
		if badge:
			badge.queue_free()
	else:
		if not badge:
			_add_stack_badge(card, count)
		else:
			badge.text = "x%d" % count


func _update_strategy_modifier_badge(card: Control, modifier: int) -> void:
	var badge := card.get_node_or_null("ModifierBadge")
	if modifier == 0:
		if badge:
			badge.queue_free()
		return
	if not badge:
		badge = Label.new()
		badge.name = "ModifierBadge"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 3)
		card.add_child(badge)
	# Card is portrait in local space; slot rotates -90° CCW for landscape display.
	# Portrait bottom-center → visual middle-right of landscape.
	# Counter-rotate badge +90° so text reads horizontally on screen.
	var bw: float = card.size.x * 0.8
	var bh: float = card.size.y * 0.15
	badge.size = Vector2(bw, bh)
	badge.pivot_offset = Vector2(bw / 2.0, bh / 2.0)
	badge.rotation = deg_to_rad(90)
	badge.position = Vector2(card.size.x * 0.5 - bw / 2.0, card.size.y * 0.75 - bh / 2.0)
	var prefix := "+" if modifier > 0 else ""
	badge.text = "%s%d" % [prefix, modifier]
	badge.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1) if modifier > 0 else Color(1.0, 0.3, 0.3, 1))


func _update_modifier_badge(card: Control, modifier: int) -> void:
	# Battle-card CP modifier badge — sits in the lower band so the green CP
	# label lines up with monster cards' green threat label (also lower).
	# Strategy cards use _update_strategy_modifier_badge instead.
	var badge := card.get_node_or_null("ModifierBadge")
	if modifier == 0:
		if badge:
			badge.queue_free()
		return
	if not badge:
		badge = Label.new()
		badge.name = "ModifierBadge"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 3)
		badge.anchor_left = 0.4
		badge.anchor_right = 0.95
		badge.anchor_top = 0.72
		badge.anchor_bottom = 0.84
		card.add_child(badge)
	var prefix := "+" if modifier > 0 else ""
	badge.text = "%s%d" % [prefix, modifier]
	badge.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1) if modifier > 0 else Color(1.0, 0.3, 0.3, 1))


func _update_threat_modifier_badge(card: Control, modifier: int) -> void:
	# Monster threat modifier badge — bottom-right band, distinct node name so it
	# can coexist with the CP modifier badge that sits one band above it.
	var badge := card.get_node_or_null("ThreatModifierBadge")
	if modifier == 0:
		if badge:
			badge.queue_free()
		return
	if not badge:
		badge = Label.new()
		badge.name = "ThreatModifierBadge"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 3)
		badge.anchor_left = 0.4
		badge.anchor_right = 0.95
		badge.anchor_top = 0.72
		badge.anchor_bottom = 0.84
		card.add_child(badge)
	var prefix := "+" if modifier > 0 else ""
	badge.text = "%s%d" % [prefix, modifier]
	badge.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1) if modifier > 0 else Color(1.0, 0.3, 0.3, 1))


func _update_rank_modifier_badge(card: Control, modifier: int) -> void:
	var badge := card.get_node_or_null("RankModifierBadge")
	if modifier == 0:
		if badge:
			badge.queue_free()
		return
	if not badge:
		badge = Label.new()
		badge.name = "RankModifierBadge"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 3)
		badge.anchor_left = 0.05
		badge.anchor_right = 0.5
		badge.anchor_top = 0.04
		badge.anchor_bottom = 0.16
		card.add_child(badge)
	var prefix := "+" if modifier > 0 else ""
	badge.text = "%s%d" % [prefix, modifier]
	badge.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1) if modifier > 0 else Color(1.0, 0.3, 0.3, 1))


func _update_monster_cp_badge(card: Control, modifier: int) -> void:
	# Monster CP modifier badge — sits one band above the threat modifier so that
	# a monster card with both CP and threat bonuses doesn't collide.
	var badge := card.get_node_or_null("MonsterCPBadge")
	if modifier == 0:
		if badge:
			badge.queue_free()
		return
	if not badge:
		badge = Label.new()
		badge.name = "MonsterCPBadge"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 3)
		badge.anchor_left = 0.15
		badge.anchor_right = 0.7
		badge.anchor_top = 0.52
		badge.anchor_bottom = 0.64
		card.add_child(badge)
	var prefix := "+" if modifier > 0 else ""
	badge.text = "CP %s%d" % [prefix, modifier]
	badge.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0, 1) if modifier > 0 else Color(1.0, 0.3, 0.3, 1))


func _add_border(control: Control) -> void:
	PlayerBoardHelpers.add_border(control, info_border_color, info_border_width)


# --- Formatting helpers ---

func _set_label_autofit(label: Label, text: String, min_size: int = 8) -> void:
	label.text = text
	_apply_autofit(label, min_size)


func _apply_autofit(label: Label, min_size: int) -> void:
	var font := label.get_theme_font("font")
	var available := label.size.x
	if available <= 0.0:
		return
	var fs := _target_value_font_size
	while fs > min_size:
		if font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= available:
			break
		fs -= 1
	label.add_theme_font_size_override("font_size", fs)


static func _format_number(value: int) -> String:
	var negative := value < 0
	var s := str(absi(value))
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return ("-" + result) if negative else result


# --- Card-back stack helpers ---

func _get_card_back_texture() -> Texture2D:
	if not _card_back_cache_loaded:
		_card_back_cache_loaded = true
		_default_card_back_tex = load(_DEFAULT_CARD_BACK_PATH)
		var cb_dir := GameSettings.get_custom_base_path().path_join("cardBack")
		var cb_path := _find_custom_file(cb_dir, "default")
		if not cb_path.is_empty():
			var image := Image.load_from_file(cb_path)
			if image:
				_custom_card_back_tex = ImageTexture.create_from_image(image)
	if _custom_card_back_tex and _should_use_custom_back():
		return _custom_card_back_tex
	return _default_card_back_tex


func _should_use_custom_back() -> bool:
	var mode: int = GameSettings.custom_card_back_mode
	if mode == 0:
		return false
	if mode == 2:
		return true
	# Mode 1: myself only
	var local_id := NetworkManager.get_local_player_id() if NetworkManager.is_multiplayer() else (NetworkManager.local_player_id if NetworkManager.local_player_id >= 0 else 0)
	return player_id == local_id


func _create_deck_stack(parent: Control, stack_arr: Array[Control], max_layers: int = -1) -> void:
	## Create a stack of card-back panels that grows/shrinks with deck size.
	## Pass max_layers=-1 (default) to use the @export config.
	var layers: int = max_layers if max_layers >= 0 else deck_stack_max_layers
	PlayerBoardHelpers.create_deck_stack(parent, stack_arr, layers, deck_stack_layer_shift, _get_card_back_texture())


func _on_discard_hover_started() -> void:
	if discard_count_badge:
		discard_count_badge.show()
	if _discard_card and _discard_card.visible and not _discard_card.card_data.is_empty():
		card_preview_requested.emit(_discard_card.card_data, 0)


func _on_discard_hover_ended() -> void:
	if discard_count_badge:
		discard_count_badge.hide()
	card_preview_cleared.emit()


func _create_count_badge() -> Label:
	return PlayerBoardHelpers.create_count_badge(
		count_badge_font_size,
		count_badge_color,
		count_badge_outline_color,
		count_badge_outline_size,
	)
