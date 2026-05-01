# Designer scratch folder

This folder ships **starter scenes** for a designer building a custom
GameBoard variant. Each scene inherits from a template — open it in
the Godot editor and tweak; production scenes are unaffected.

## What's here

| File | Inherits from | Purpose |
| --- | --- | --- |
| `DesignerGameBoard.tscn` | `scenes/board/GameBoardTemplate.tscn` | Top-level scene. Auto-discovered by the 🧪 picker in MainMenu (path: `scenes/board/designer/DesignerGameBoard.tscn`). |
| `DesignerPlayerBoard.tscn` | `scenes/board/PlayerBoardTemplate.tscn` | Per-side board. Customize zone positions, label sizes, playmat artwork, the deck/discard/monster info zones, etc. |
| `DesignerOverlayPack.tscn` | `scenes/board/overlays/DefaultOverlayPack.tscn` | Bundle of modal overlay scenes (deck search, card select, deck arrange, choice prompt, etc.). |

## Quick workflow

1. **Open `DesignerGameBoard.tscn`.** It already has both seats with
   PlayerBoardTemplate children, the HUD, ActionPanel, LogPanel,
   and overlays. Run via the 🧪 button in MainMenu.
2. **To customize the player board:**
   - Edit `DesignerPlayerBoard.tscn` — move zones, change label sizes,
     swap the playmat texture, etc. The PlayerBoardTemplate inheritance
     means you can override any property without losing structure.
   - In `DesignerGameBoard.tscn`, click each seat's inherited
     `PlayerBoard` instance → in the inspector, click the scene-folder
     icon → swap to `DesignerPlayerBoard.tscn`. Or set the seat's
     `player_board_scene` field directly.
3. **To customize overlays:**
   - Edit `DesignerOverlayPack.tscn` — add/remove overlay variants,
     restyle the inherited ones.
   - In `DesignerGameBoard.tscn`, replace the inherited
     `DefaultOverlayPack` instance with `DesignerOverlayPack.tscn`
     (right-click → Change Scene File). Keep the **node name** as
     `DefaultOverlayPack` — `GameBoardBase` resolves the overlay pack
     by that name when the inspector slot is empty.
4. **To customize the GameBoard layout itself:**
   - Edit `DesignerGameBoard.tscn` directly — move the TopBar,
     LogPanel, ActionPanel, etc. The inherited tree shows everything
     `GameBoardTemplate` provides; override any property in the
     inspector.

## Inspector knobs (shipped from Phase 17)

After Phase 17, every layout/styling constant the templates were
hardcoding is now exposed as `@export`. Highlights:

- **PlayerBoard / Layout fitting**: `maintain_aspect`, `aspect_ratio`,
  `content_rect_normal/mirrored` — toggle off to disable runtime
  aspect-fitting and use editor anchors as-is.
- **PlayerBoard / Count badges**: font size, color, outline.
- **PlayerBoard / Info zone borders**: color, width.
- **PlayerBoard / Deck stack**: max layers, layer shift.
- **HandSlot / Positioning**: `auto_position` toggle (false → designer
  owns placement), `anchor_edge`, `width_pct`.
- **HoverPreview / Card layout**: `card_aspect_ratio`, `padding`,
  `rotate_strategy`.
- **ChoicePromptOverlay / Buttons**: `button_min_size`,
  `button_separation`.

See `docs/new_game_board.md` for the full HUD primitives table and
the seat / module composition pattern.

## Cross-scene multiplayer contract

The **root node of `DesignerGameBoard.tscn` must stay named
`GameBoard`** — the network layer routes RPCs through this stable
NodePath. Inheritance from `GameBoardTemplate` already satisfies this;
just don't rename the root.

`docs/new_game_board.md` § "Cross-scene multiplayer contract" covers
this in detail.
