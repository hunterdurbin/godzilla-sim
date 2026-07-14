#!/bin/bash
# Dedicated-server integration harness: boots the headless server, then plays
# N full random games (two headless clients per game) and checks every log
# for desync warnings and script errors.
#
# Usage: ./tests/harness/run_harness.sh [num_games] [godot_binary]

set -u
GAMES="${1:-3}"
GODOT="${2:-godot}"
PORT="${PORT:-12091}"
LOGDIR="$(mktemp -d /tmp/godzilla_harness.XXXXXX)"
FAIL=0

cleanup() {
  pkill -f "ServerMain.tscn" 2>/dev/null
  pkill -f "HeadlessTestClient" 2>/dev/null
}
trap cleanup EXIT

cleanup; sleep 1
"$GODOT" --headless --path . scenes/server/ServerMain.tscn -- --port=$PORT --no-stats > "$LOGDIR/server.log" 2>&1 &
sleep 5
if ! grep -q "Listening on port" "$LOGDIR/server.log"; then
  echo "FAIL: server did not start"; cat "$LOGDIR/server.log"; exit 1
fi

for i in $(seq 1 "$GAMES"); do
  SEED=$((1000 + i))
  echo "=== Game $i (seed $SEED) ==="
  "$GODOT" --headless --path . tests/harness/HeadlessTestClient.tscn -- --port=$PORT --create --play --seed=$SEED > "$LOGDIR/g${i}_a.log" 2>&1 &
  CA=$!
  sleep 2
  "$GODOT" --headless --path . tests/harness/HeadlessTestClient.tscn -- --port=$PORT --join --play --seed=$SEED > "$LOGDIR/g${i}_b.log" 2>&1 &
  CB=$!
  wait $CA; EA=$?
  wait $CB; EB=$?
  RESULT=$(grep -hE "Match [0-9]+ ended" "$LOGDIR/g${i}_a.log" | head -1)
  echo "  exits: creator=$EA joiner=$EB | $RESULT"
  if [ "$EA" -ne 0 ] || [ "$EB" -ne 0 ]; then
    FAIL=1
    echo "  --- creator tail ---"; tail -6 "$LOGDIR/g${i}_a.log"
    echo "  --- joiner tail ---"; tail -6 "$LOGDIR/g${i}_b.log"
  fi
done

DESYNCS=$(grep -l "DESYNC" "$LOGDIR"/*.log 2>/dev/null | wc -l | tr -d ' ')
ERRORS=$(grep -l "SCRIPT ERROR" "$LOGDIR"/*.log 2>/dev/null | wc -l | tr -d ' ')
echo "=== Summary: $GAMES games, files-with-desyncs=$DESYNCS, files-with-script-errors=$ERRORS (logs: $LOGDIR) ==="
if [ "$DESYNCS" != "0" ]; then grep -h "DESYNC" "$LOGDIR"/*.log | head -5; FAIL=1; fi
if [ "$ERRORS" != "0" ]; then grep -hA3 "SCRIPT ERROR" "$LOGDIR"/*.log | head -20; FAIL=1; fi
[ "$FAIL" -eq 0 ] && echo "HARNESS PASS" || echo "HARNESS FAIL"
exit $FAIL
