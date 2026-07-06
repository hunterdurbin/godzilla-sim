# Steam Input API — Stage 2 Design Note (not yet implemented)

Status: **design only.** Stage 1 (shipped) is Gamepad Emulation compatibility:
`GlyphDB.detect_type` sees through "Steam Virtual Gamepad" names via
`Input.get_joy_info()` vendor ids, Steam Deck maps to the `generic` glyph set
(which is Kenney's Steam Deck art), and Options → Controller has a manual
"Button Icons" override for masked devices. That covers players who add the
game as a non-Steam game or run it on Steam Deck.

Stage 2 — full **Steam Input API** integration — only makes sense if the game
ships on Steam with its own AppID. What it involves (per
https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_devs):

## Dependencies

- **GodotSteam** (GDExtension build; no engine recompile) added under
  `addons/`, plus `steam_appid.txt` in dev builds. Every desktop export
  preset gains the GDExtension libraries; mobile/web presets exclude them.
- A Steam **AppID**. Development/testing without one: SpaceWar (AppID 480)
  and `steam://forceinputappid/480` to pin a config to the dev window.

## Action manifest

`game_actions_<appid>.vdf` mapping our existing logical actions onto Steam
action sets — the two-layer design was built for this seam:

- Action set `menu`: `pad_confirm`, `pad_cancel`, `pad_nav_*` (StickPadGyro
  `absolute_mouse` optional for cursor play).
- Action set `in_game`: everything in `GlyphDB.default_map()` plus nav.
- Localization block sourced from `translations/strings.csv` STR_PAD_* keys.

At runtime, switch action sets on `GamepadHelper` focus-context changes
(board context → `in_game`, anything else → `menu`).

## Input pipeline

`GamepadInput` grows a strategy split like spire's
`SteamControllerInputStrategy`: when `SteamInput.init()` succeeds, poll
`run_frame()` + digital/analog action data per frame and inject the same
logical `InputEventAction`s we inject today (physical `controller_*` actions
bypass entirely); otherwise fall back to the current SDL path unchanged.

## Glyphs

`GamepadInput.get_glyph()` is the seam: under Steam Input, resolve
`get_digital_action_origins()` → `get_glyph_png_for_action_origin()` and
load the returned PNG path (cache per origin; Valve says poll origins every
frame since the user can rebind live — cheap dictionary compare before
re-resolving textures). `ControllerGlyph` needs no changes.

## Rebinding

When Steam Input is active, Steam owns rebinding: hide the Options rebind
rows (keep the glyph-style row hidden too — origins carry the art) and show
a "Configure in Steam" button (`show_binding_panel()`).

## Testing

- Steam-less CI stays on the SDL path (strategy falls back when
  `SteamInput.init()` fails), so the existing `tests/unit/gamepad/` suite is
  unaffected.
- Manual: SpaceWar AppID, one pass per controller type, verifying glyph
  origin resolution and action-set switching at the board/menu boundary.
