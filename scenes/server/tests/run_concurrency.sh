#!/bin/bash
# Concurrency drill: one server process, N full random games running AT THE
# SAME TIME (the sequential harness never exercises multi-room coexistence).
# Reports per-game results, peak server memory, and error/desync counts.
#
# Usage: ./scenes/server/tests/run_concurrency.sh [num_concurrent_games] [godot_binary]

set -u
GAMES="${1:-4}"
GODOT="${2:-godot}"
PORT=12091
LOGDIR="$(mktemp -d /tmp/godzilla_conc.XXXXXX)"
FAIL=0

cleanup() {
  pkill -f "ServerMain.tscn" 2>/dev/null
  pkill -f "HeadlessTestClient" 2>/dev/null
}
trap cleanup EXIT

cleanup; sleep 1
"$GODOT" --headless --path . scenes/server/ServerMain.tscn -- --port=$PORT --no-stats > "$LOGDIR/server.log" 2>&1 &
SERVER_PID=$!
sleep 5
if ! grep -q "Listening on port" "$LOGDIR/server.log"; then
  echo "FAIL: server did not start"; cat "$LOGDIR/server.log"; exit 1
fi
RSS_START=$(ps -o rss= -p $SERVER_PID | tr -d ' ')

PIDS=""
for i in $(seq 1 "$GAMES"); do
  SEED=$((4000 + i))
  CF="$LOGDIR/code_$i.txt"
  "$GODOT" --headless --path . scenes/server/tests/HeadlessTestClient.tscn -- --create --play --seed=$SEED --codefile="$CF" > "$LOGDIR/g${i}_a.log" 2>&1 &
  PIDS="$PIDS $!"
  sleep 0.5
  "$GODOT" --headless --path . scenes/server/tests/HeadlessTestClient.tscn -- --join --play --seed=$SEED --codefile="$CF" > "$LOGDIR/g${i}_b.log" 2>&1 &
  PIDS="$PIDS $!"
done
echo "=== $GAMES games launched concurrently ($((GAMES * 2)) clients) ==="

# Sample peak server RSS while the games run
RSS_PEAK=$RSS_START
( while kill -0 $SERVER_PID 2>/dev/null; do sleep 2; done ) &
for pid in $PIDS; do
  while kill -0 "$pid" 2>/dev/null; do
    RSS=$(ps -o rss= -p $SERVER_PID 2>/dev/null | tr -d ' ')
    [ -n "$RSS" ] && [ "$RSS" -gt "$RSS_PEAK" ] && RSS_PEAK=$RSS
    sleep 2
  done
done

for i in $(seq 1 "$GAMES"); do
  RESULT=$(grep -hE "Match [0-9]+ ended" "$LOGDIR/g${i}_a.log" | head -1)
  PASSED=$(grep -c "PASS (full" "$LOGDIR/g${i}_a.log")
  echo "  game $i: pass=$PASSED | ${RESULT:-NO RESULT}"
  [ "$PASSED" -eq 1 ] || FAIL=1
done

ROOMS_PEAK=$(grep -c "Starting match" "$LOGDIR/server.log")
DESYNCS=$(grep -l "DESYNC" "$LOGDIR"/*.log 2>/dev/null | wc -l | tr -d ' ')
ERRORS=$(grep -l "SCRIPT ERROR" "$LOGDIR"/*.log 2>/dev/null | wc -l | tr -d ' ')
echo "=== matches started: $ROOMS_PEAK | server RSS: $((RSS_START/1024))MB -> peak $((RSS_PEAK/1024))MB | desync-files=$DESYNCS error-files=$ERRORS (logs: $LOGDIR) ==="
if [ "$DESYNCS" != "0" ]; then grep -h "DESYNC" "$LOGDIR"/*.log | head -5; FAIL=1; fi
if [ "$ERRORS" != "0" ]; then grep -hA3 "SCRIPT ERROR" "$LOGDIR"/*.log | head -20; FAIL=1; fi
[ "$FAIL" -eq 0 ] && echo "CONCURRENCY PASS" || echo "CONCURRENCY FAIL"
exit $FAIL
