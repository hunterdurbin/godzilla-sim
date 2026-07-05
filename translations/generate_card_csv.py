#!/usr/bin/env python3
"""Regenerate translations/cards.csv from card_data.gd and the *_card_effects_ja.txt files.

The game uses card IDs like EBP01-001. The JP scrape files use the same IDs without
the leading E (BP01-001). Some entries also have a trailing + for reprint variants
(BP01-001+) — we prefer the non-+ entry because it keeps explanatory parentheticals
that match the English long-form text.
"""

import csv
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
CARD_DATA_GD = REPO / "scripts" / "cards" / "card_data.gd"
JA_SOURCES = HERE / "ja_sources"
OUT_CSV = HERE / "cards.csv"

# Regex for one card dict in card_data.gd. Only captures id, name, description.
# Descriptions may be missing (some cards have no effect field — but most do).
CARD_ID_RE = re.compile(r'"id"\s*:\s*"([^"]+)"')
CARD_NAME_RE = re.compile(r'"name"\s*:\s*"((?:[^"\\]|\\.)*)"')
CARD_DESC_RE = re.compile(r'"description"\s*:\s*"((?:[^"\\]|\\.)*)"')

# JP scrape header: === BP01-001 | ゴジラ(1954) === (also matches PR-005, SC01-001, BP02-T01)
JP_HEADER_RE = re.compile(r'^===\s+([A-Z]+\d*-(?:T\d+|\d+)\+?)\s*\|\s*(.+?)\s*===\s*$')

# Any other "=== ... ===" line is a non-card boundary (e.g. the "Rage-GZ30"
# rage-token entries at the tail of scrape files). It must close the current
# entry so its lines don't leak into the previous card's description.
JP_BOUNDARY_RE = re.compile(r'^===.*===\s*$')


def parse_card_data() -> list[dict]:
    """Return list of {id, name, description} for every card in card_data.gd."""
    text = CARD_DATA_GD.read_text(encoding="utf-8")
    cards = []
    # Walk through each braced card block by splitting on '"id":' as a coarse anchor.
    # Simpler: iterate line-based, collecting id→(name, desc) per logical block.
    current: dict = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        m_id = CARD_ID_RE.search(line)
        if m_id:
            if current.get("id"):
                cards.append(current)
            current = {"id": m_id.group(1), "name": "", "description": ""}
            continue
        m_name = CARD_NAME_RE.search(line)
        if m_name and current and not current.get("name"):
            current["name"] = m_name.group(1)
            continue
        m_desc = CARD_DESC_RE.search(line)
        if m_desc and current and not current.get("description"):
            current["description"] = m_desc.group(1)
            continue
    if current.get("id"):
        cards.append(current)
    return cards


def parse_jp_file(path: Path) -> list[tuple[str, str, str]]:
    """Return list of (jp_id, name_ja, desc_ja) triples from a scrape file."""
    entries: list[tuple[str, str, str]] = []
    current_id: str | None = None
    current_name: str = ""
    current_lines: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("#"):
            continue
        m = JP_HEADER_RE.match(raw)
        if m:
            if current_id:
                entries.append((current_id, current_name, "\n".join(current_lines).strip()))
            current_id = m.group(1)
            current_name = m.group(2)
            current_lines = []
            continue
        if JP_BOUNDARY_RE.match(raw):
            if current_id:
                entries.append((current_id, current_name, "\n".join(current_lines).strip()))
            current_id = None
            continue
        if current_id is not None:
            current_lines.append(raw)
    if current_id:
        entries.append((current_id, current_name, "\n".join(current_lines).strip()))
    return entries


def build_jp_index(translations_dir: Path) -> dict[str, tuple[str, str]]:
    """Build map from base JP id (no + suffix) to (name, desc).
    Prefers the non-+ variant when both exist because its text matches the
    English long-form with parenthetical explanations.
    """
    index: dict[str, tuple[str, str]] = {}
    for jp_file in sorted(translations_dir.glob("*_card_effects_ja.txt")):
        for jp_id, name_ja, desc_ja in parse_jp_file(jp_file):
            base_id = jp_id.rstrip("+")
            is_plus = jp_id.endswith("+")
            if base_id in index and is_plus:
                continue  # already have non-+ entry; don't overwrite
            index[base_id] = (name_ja, desc_ja)
    return index


def en_id_to_jp_id(en_id: str) -> str:
    """EBP01-001 -> BP01-001; ESD01-003 -> SD01-003; EPR-001 -> PR-001 (not in JP files)."""
    return en_id[1:] if en_id.startswith("E") else en_id


def unescape_gdscript(s: str) -> str:
    """Convert GDScript string escapes (\\n, \\t, \\", \\\\) to actual characters.
    Avoids unicode_escape because it mangles real UTF-8 chars like U+2019 (’).
    """
    out: list[str] = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == "n":
                out.append("\n")
            elif nxt == "t":
                out.append("\t")
            elif nxt == "r":
                out.append("\r")
            elif nxt == '"':
                out.append('"')
            elif nxt == "'":
                out.append("'")
            elif nxt == "\\":
                out.append("\\")
            else:
                # Unknown escape — preserve literally.
                out.append(c)
                out.append(nxt)
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def main() -> None:
    cards = parse_card_data()
    print(f"Parsed {len(cards)} cards from card_data.gd")

    jp_index = build_jp_index(JA_SOURCES)
    print(f"Indexed {len(jp_index)} JP entries from scrape files")

    rows = [["keys", "en", "ja"]]
    translated_count = 0
    missing_count = 0
    for card in cards:
        en_id = card["id"]
        en_name = unescape_gdscript(card["name"])
        en_desc = unescape_gdscript(card["description"])
        jp_id = en_id_to_jp_id(en_id)
        ja = jp_index.get(jp_id)
        if ja:
            name_ja, desc_ja = ja
            translated_count += 1
        else:
            name_ja, desc_ja = "", ""
            missing_count += 1

        rows.append([f"CARD_{en_id}_NAME", en_name, name_ja])
        rows.append([f"CARD_{en_id}_DESC", en_desc, desc_ja])

    print(f"Translated: {translated_count}, Missing JP: {missing_count}")

    with OUT_CSV.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        writer.writerows(rows)
    print(f"Wrote {len(rows) - 1} translation rows to {OUT_CSV}")


if __name__ == "__main__":
    main()
