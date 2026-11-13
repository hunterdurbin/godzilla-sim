#!/bin/bash
# Regenerate rules.txt (greppable text) from the comprehensive rules PDF.
# Needs pdftotext (poppler: `brew install poppler`).
#
# Usage: comprehensive_rules/extract_text.sh [pdf]
#   pdf  default: the newest *Comprehensive-Rules.pdf in this directory
#
# Cleanup so `grep -A4 '^5\.11\.1\.1\.'` finds a rule with its text:
#   - drops zero-width / direction marks the PDF puts after rule numbers
#   - joins a rule number left alone on its line with the line after it
set -eu
cd "$(dirname "$0")"

PDF="${1:-$(ls -1 *Comprehensive-Rules.pdf | sort | tail -1)}"
command -v pdftotext > /dev/null || { echo "pdftotext not found (brew install poppler)"; exit 1; }

pdftotext -enc UTF-8 "$PDF" - | python3 -c '
import re, sys
text = re.sub("[​‎‏﻿]", "", sys.stdin.read())
# "5.11.1.1.\nIf a battle card ..." -> "5.11.1.1. If a battle card ..."
text = re.sub(r"(?m)^(\d+(?:\.\d+)*\.)[ \t]*\n(?=\S)", r"\1 ", text)
sys.stdout.write(text)
' > rules.txt

echo "Wrote $(wc -l < rules.txt | tr -d " ") lines to comprehensive_rules/rules.txt from $PDF"
