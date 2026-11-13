#!/usr/bin/env python3
"""Guard: per-card effect scripts await every engine coroutine they call.

A GDScript function containing `await` is a coroutine. Calling one without
`await` starts it and returns immediately, so the card script runs on while
the engine is still mid-move (e.g. EBP03-058 destroyed its zone before the
un-awaited move_zone_stack had finished). GDScript has no warning for this.

The coroutine set is derived from the source, so it never goes stale:
every function in scripts/effects/effect_handler.gd (called as
`<...>effect_handler.name(` / `handler.name(`) and scripts/effects/effect_context.gd
(called as `ctx.name(`) whose body contains `await`.

Scans per-card scripts only: scripts/effects/<set>/*.gd. No allowlist — the
tree is clean; await the call.

Usage: python3 scripts/tools/check_card_unawaited_coroutines.py
"""
import os
import re
import sys

from gd_ratchet import EFFECTS_DIR, ROOT, card_scripts, strip_comment
FUNC_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(")
# Optional `await`, then a receiver chain ending in effect_handler/handler/ctx, then .name(
CALL_RE = re.compile(r"(\bawait\s+)?\b((?:[A-Za-z_]\w*\.)*?)(effect_handler|handler|ctx)\.([A-Za-z_]\w*)\s*\(")


def coroutines(path):
    names = set()
    current = None
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            m = FUNC_RE.match(raw)
            if m:
                current = m.group(1)
            elif current and re.search(r"\bawait\b", strip_comment(raw)):
                names.add(current)
    return names


def main():
    handler_co = coroutines(os.path.join(EFFECTS_DIR, "effect_handler.gd"))
    context_co = coroutines(os.path.join(EFFECTS_DIR, "effect_context.gd"))
    if not handler_co:
        print("check_card_unawaited_coroutines: found no EffectHandler coroutines — parser broken?")
        return 1
    violations = []
    for path in card_scripts():
        with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
            for lineno, raw in enumerate(fh, 1):
                line = strip_comment(raw)
                for m in CALL_RE.finditer(line):
                    awaited, _chain, receiver, name = m.groups()
                    pool = context_co if receiver == "ctx" else handler_co
                    if name in pool and not awaited:
                        violations.append("%s:%d  %s()  ->  %s" % (path, lineno, name, raw.strip()))
    for v in violations:
        print("UNAWAITED coroutine  " + v)
    if violations:
        print("\nThese engine functions contain `await`; call them with `await` so the"
              " card script waits for the engine to finish.")
        return 1
    print("card unawaited coroutines: OK (%d handler + %d context coroutines)"
          % (len(handler_co), len(context_co)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
