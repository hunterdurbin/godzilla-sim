#!/usr/bin/env bash
# Compares cards from the Godzilla TCG API against card_data.gd
# and reports any missing cards, grouped by set.

set -euo pipefail

API_BASE="https://api.godzillatcg.com"
CARD_DATA="$(dirname "$0")/../cards/card_data.gd"

if [ ! -f "$CARD_DATA" ]; then
    echo "Error: card_data.gd not found at $CARD_DATA"
    exit 1
fi

# Extract existing card IDs from card_data.gd
echo "Reading existing cards from card_data.gd..."
EXISTING=$(grep -o '"id": "[^"]*"' "$CARD_DATA" | sed 's/"id": "//;s/"//' | sort -u)
EXISTING_COUNT=$(echo "$EXISTING" | wc -l | tr -d ' ')
echo "Found $EXISTING_COUNT cards in card_data.gd"

# Fetch all cards from API (paginated, max 100 per request)
echo ""
echo "Fetching cards from API..."
ALL_API_CARDS=""
OFFSET=0
LIMIT=100
TOTAL=""

while true; do
    RESPONSE=$(curl -sf "${API_BASE}/cards?limit=${LIMIT}&offset=${OFFSET}")

    if [ -z "$TOTAL" ]; then
        TOTAL=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
        echo "API reports $TOTAL total cards"
    fi

    # Extract card data as JSON lines: card_number|name|type|rank|colors|traits|threat_level|counter_power|invasion_icon
    PAGE_CARDS=$(echo "$RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for card in data['cards']:
    v = card['type']['value']
    num = v.get('card_number', '')
    if num:
        name = v.get('name', '')
        ctype = v.get('type', '')
        rank = v.get('rank', '')
        colors = ','.join(v.get('colors', []))
        traits = ','.join(v.get('traits', []))
        threat = v.get('threat_level', '0')
        counter = v.get('counter_power', '0')
        invasion = v.get('invasion_icon_value', 0)
        desc = v.get('description', '').replace('\n', '\\\\n')
        print(f'{num}|{name}|{ctype}|{rank}|{colors}|{traits}|{threat}|{counter}|{invasion}|{desc}')
")

    if [ -n "$PAGE_CARDS" ]; then
        if [ -n "$ALL_API_CARDS" ]; then
            ALL_API_CARDS="${ALL_API_CARDS}
${PAGE_CARDS}"
        else
            ALL_API_CARDS="$PAGE_CARDS"
        fi
    fi

    OFFSET=$((OFFSET + LIMIT))
    if [ "$OFFSET" -ge "$TOTAL" ]; then
        break
    fi
done

API_COUNT=$(echo "$ALL_API_CARDS" | wc -l | tr -d ' ')
echo "Fetched $API_COUNT cards from API"

# Find missing cards
echo ""
echo "============================================"
echo "  MISSING CARDS REPORT"
echo "============================================"

MISSING=""
MISSING_COUNT=0

while IFS='|' read -r card_number name ctype rank colors traits threat counter invasion desc; do
    if ! echo "$EXISTING" | grep -qx "$card_number"; then
        if [ -n "$MISSING" ]; then
            MISSING="${MISSING}
${card_number}|${name}|${ctype}|${rank}|${colors}|${traits}|${threat}|${counter}|${invasion}|${desc}"
        else
            MISSING="${card_number}|${name}|${ctype}|${rank}|${colors}|${traits}|${threat}|${counter}|${invasion}|${desc}"
        fi
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done <<< "$ALL_API_CARDS"

if [ "$MISSING_COUNT" -eq 0 ]; then
    echo ""
    echo "All API cards are present in card_data.gd!"
    exit 0
fi

echo ""
echo "Found $MISSING_COUNT missing cards:"
echo ""

# Group by set and display
CURRENT_SET=""
echo "$MISSING" | sort | while IFS='|' read -r card_number name ctype rank colors traits threat counter invasion desc; do
    SET_ID="${card_number%%-*}"

    if [ "$SET_ID" != "$CURRENT_SET" ]; then
        CURRENT_SET="$SET_ID"
        # Check if this is a new set not in card_data.gd
        if grep -q "${SET_ID}_CARDS" "$CARD_DATA"; then
            echo ""
            echo "--- $SET_ID (existing set) ---"
        else
            echo ""
            echo "--- $SET_ID (NEW SET - needs to be created) ---"
        fi
    fi

    printf "  %-15s %-30s %-10s Rank:%-3s Colors:%-12s Traits:%s\n" \
        "$card_number" "$name" "$ctype" "$rank" "$colors" "$traits"
done

echo ""
echo "============================================"
echo "  SUMMARY"
echo "============================================"
echo "Cards in card_data.gd: $EXISTING_COUNT"
echo "Cards in API:          $API_COUNT"
echo "Missing cards:         $MISSING_COUNT"

# List new sets that need to be created
NEW_SETS=$(echo "$MISSING" | cut -d'|' -f1 | cut -d'-' -f1 | sort -u | while read -r set_id; do
    if ! grep -q "${set_id}_CARDS" "$CARD_DATA"; then
        echo "$set_id"
    fi
done)

if [ -n "$NEW_SETS" ]; then
    echo ""
    echo "New sets to create in card_data.gd:"
    echo "$NEW_SETS" | while read -r set_id; do
        COUNT=$(echo "$MISSING" | grep "^${set_id}-" | wc -l | tr -d ' ')
        echo "  - ${set_id}_CARDS ($COUNT cards)"
    done
fi
