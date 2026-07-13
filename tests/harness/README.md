# tests/harness/ — multiplayer integration harness

Spins up the dedicated server (`scenes/server/ServerMain.tscn`) plus paired
headless clients that play full bot-driven matches against each other, then
greps every log for desyncs and script errors.

## Runners

```bash
# N sequential games (server + creator + joiner per game):
./tests/harness/run_harness.sh 3 <godot>

# N concurrent games against one server (room-code isolation):
./tests/harness/run_concurrency.sh 5 <godot>
```

Default port 12091. Logs land in a `mktemp -d` dir printed in the summary
line (`/tmp/godzilla_harness.XXXXXX`: `server.log`, `g<i>_a.log`,
`g<i>_b.log`).

**Pass contract:** the runner greps all logs for `DESYNC` and
`SCRIPT ERROR` and prints
`=== Summary: N games, files-with-desyncs=0, files-with-script-errors=0 ===`
followed by `HARNESS PASS`. Any non-zero count = failure; read the named
log dir. (The trailing `Terminated: 15` line is the runner killing the
server — normal.)

## Pieces

| File | Role |
|---|---|
| `HeadlessTestClient.tscn` / `headless_test_client.gd` | Headless client; flags: `--port=N --create\|--join [--play] [--seed=N] [--codefile=F] [--rematch[=N]]` (`--rematch=N` plays N rematches — N+1 full games; both clients must pass it) |
| `OnlinePilot.tscn` / `online_pilot_boot.gd` + `online_pilot.gd` | HEADFUL smoke pilot: real client + real GameBoard driven through the actual UI (buttons/overlay cards/slots), screenshots every modal kind, plays full games + rematches (one with a deck change), leave-dialog and claim-win drills. Flags: `--create\|--join --port=N [--seed=N] [--rematches=N] [--codefile=F] [--drill=claimwin] [--shots=DIR]` (or `SMOKE_SHOT_DIR`). Greps: `[Pilot] PASS` / `[Pilot] FAIL` |
| `stub_client_board.gd` | Headless stand-in for GameBoard — one of the THREE implementations of the `_board` duck-typed contract (with `scenes/board/game_board.gd` and `scripts/server/headless_board.gd`). **RPC-surface changes must be mirrored here.** |
| `RealClientSmoke.tscn` / `real_client_smoke.gd` | Smoke test driving the real client scene flow |
| `BranchRpcSpike.tscn` / `branch_rpc_spike.gd` + `spike_sync.gd` | RPC branching spike (historical repro scene) |

Unit tests can't catch RPC/board-contract breakage (they don't run the
session layer against all three boards) — this harness is the gate for that.
