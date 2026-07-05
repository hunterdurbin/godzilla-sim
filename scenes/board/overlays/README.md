# scenes/board/overlays/ — modal card UIs

Overlays pop over the board for card-level interactions. Shared plumbing:
`overlay_grid_util.gd` (grid sizing) and `minimize_chip.gd` (collapse an
overlay to a chip so the player can inspect the board underneath).

| Overlay | Purpose |
|---|---|
| `CardZoomOverlay` | Full-size card inspection (hover/long-press zoom) |
| `CardSelectOverlay` | Pick N cards (discard costs, effect targets) |
| `DeckSearchOverlay` | Search-your-deck effects |
| `DeckArrangeOverlay` | Reorder-top-of-deck effects |
| `DiscardViewOverlay` / `MonsterDeckViewOverlay` / `ZoneStackViewOverlay` | Read-only pile viewers — all three attach the shared `card_grid_viewer.gd` |
| `active_ability_banner.gd` / `turn_toast.gd` | Transient banners |

Conventions:

- Overlays are full-rect: bake `anchors_preset=15` + grow flags into the
  .tscn (not `_ready`).
- Effect flows AWAIT overlay close — a visible enabled "Close" button blocks
  phase advance until pressed (relevant to headless drivers/tests).
- Mini card previews inside overlays must be Container-wrapped or Card.tscn
  snaps to 150×210; tag wrapper nodes with meta, not names.
- Multiplayer: client-side pick results arrive as JSON (int enums → floats)
  — re-map to canonical dicts by id before use.
