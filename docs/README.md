# docs/ — cross-cutting documentation

Subsystem docs live INSIDE their directories (`scripts/*/README.md`,
`scenes/*/README.md`, `tests/*/README.md`, `assets/README.md`,
`translations/README.md`) — this folder holds only what spans subsystems.

| Item | What it is |
|---|---|
| `restructure/` | The 2026-07 project restructure: phase plan, conventions, STATE handoff log, baselines |
| `game-board-architecture.md` | GameBoard/session/module architecture deep-dive |
| `graphs/` | Graphviz diagrams (`.dot` + rendered `.png`): architecture_overview, call_categories, standby_resolution, turn_lifecycle. Regenerate: `dot -Tpng x.dot -o x.png` |
| `bot-decisioning-paths/` | Bot decision-path diagram (+ `.dot`) |
| `combos/` | Shin combo path analysis (+ `.dot`) |
| `ios-sideloading.md` | iOS sideloading guide (AltStore/SideStore) |

Rendered `.png`s are committed so the docs read without Graphviz installed —
update both files when a diagram changes.
