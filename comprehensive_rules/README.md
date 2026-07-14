# comprehensive_rules/ — official game rules

`251223-v1.1-Godzilla-TCG-Comprehensive-Rules.pdf` — the official Godzilla
TCG comprehensive rules (v1.1, 2025-12-23). The `.gdignore` keeps Godot from
importing this directory.

Engine code cites rules by section number — e.g.
`scripts/effects/standby_resolver.gd` implements "rule 10.4.3" (standby
resolution ordering). When a comment says "per rule N.N.N", this PDF is the
source of truth.

Quick orientation: 2 players, 8 zones + 2 strategy zones; win by invading
past zone 8, or when the opponent can't rank up while countered. Turn flow:
Start → Main → Counter → End. Threat = base + rage × 5000. Deck rules live in
`scripts/cards/deck_validator.gd` (50-card main deck, 4 monsters rank 1–4,
≤10 invade-2 cards, …).

When a new rules version releases, drop the new PDF here (keep the dated
filename scheme) and update this README.
