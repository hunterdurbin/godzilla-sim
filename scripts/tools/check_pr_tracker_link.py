#!/usr/bin/env python3
"""Guard: a PR body closes its tracker issue, or says it closes none.

Tracker issues live in the separate repo hunterdurbin/godzilla-sim-issue-tracker
(docs/agents/issue-tracker.md). GitHub closes one when a merged code PR's body
carries a closing keyword with the fully-qualified reference:

    Closes hunterdurbin/godzilla-sim-issue-tracker#13

Any other wording ("Implements", "Part of", a bare `#13`, which means a
code-repo PR) leaves the ticket open after the merge. A PR that finishes no
ticket (docs, tooling, a partial step) says so on its own line:

    Tracker: none

Passes when the body has either. A parent ticket ("Part of #11") is closed by
hand once its last child closes.

Also warns (never fails) on each bare `#N` outside code (fenced blocks and
inline `code` spans, where it is an example), as the
commit-msg hook does (check_commit_msg_refs.py): in this repo it links a
code-repo PR, so a tracker ticket or a grilling decision row needs the
full `hunterdurbin/godzilla-sim-issue-tracker#N`. In CI the warning is a
GitHub annotation on the check run; run this on the body before
`gh pr create` to fix it up front.

Usage: PR_BODY="..." python3 scripts/tools/check_pr_tracker_link.py
       python3 scripts/tools/check_pr_tracker_link.py < body.md
"""
import os
import re
import sys

from check_commit_msg_refs import bare_refs

TRACKER = "hunterdurbin/godzilla-sim-issue-tracker"
CLOSES_RE = re.compile(
    r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b:?\s+" + re.escape(TRACKER) + r"#\d+",
    re.IGNORECASE)
NONE_RE = re.compile(r"^\s*Tracker:\s*none\b", re.IGNORECASE | re.MULTILINE)
BARE_CLOSE_RE = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b:?\s+#\d+", re.IGNORECASE)


def check(body: str) -> str:
    """Return "" when the body passes, else the reason it fails."""
    if CLOSES_RE.search(body) or NONE_RE.search(body):
        return ""
    if BARE_CLOSE_RE.search(body):
        return ("a bare `closes #N` targets this code repo, not the tracker: write "
                "`Closes %s#N`" % TRACKER)
    return ("no closing keyword for a tracker issue: add `Closes %s#N` (one per "
            "finished ticket), or a `Tracker: none` line if this PR finishes none" % TRACKER)


def bare_body_refs(body: str) -> list:
    """Bare `#N` refs in the body, skipping fenced blocks and inline code."""
    prose, in_fence = [], False
    for line in body.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            prose.append(re.sub(r"`[^`]*`", "", line))
    return bare_refs("\n".join(prose))


def self_test() -> bool:
    cases = {
        "Closes hunterdurbin/godzilla-sim-issue-tracker#13": True,
        "Part of #11 — fixes hunterdurbin/godzilla-sim-issue-tracker#8.": True,
        "Resolves: hunterdurbin/godzilla-sim-issue-tracker#2": True,
        "Docs only.\n\nTracker: none\n": True,
        "Implements hunterdurbin/godzilla-sim-issue-tracker#12": False,
        "Part of hunterdurbin/godzilla-sim-issue-tracker#11": False,
        "Closes #13": False,
        "": False,
        "The tracker: none of these apply": False,  # not on its own line
    }
    ok = True
    ref_cases = {
        "Implements the parent (#35), decisions 18-21.": ["35"],
        "Follows hunterdurbin/godzilla-sim-issue-tracker#35 row 20.": [],
        "```text\n# Fixes #12\n```\nok": [],
        "## Summary": [],
        "On `Part of #35 …` it warns; on #7 too.": ["7"],
    }
    for body, expected in ref_cases.items():
        if bare_body_refs(body) != expected:
            print("check_pr_tracker_link.py self-test FAILED (bare refs) on: %r" % body)
            ok = False
    for body, expected in cases.items():
        if (check(body) == "") != expected:
            print("check_pr_tracker_link.py self-test FAILED on: %r" % body)
            ok = False
    return ok


def main() -> int:
    if not self_test():
        return 1
    body = os.environ.get("PR_BODY")
    if body is None:
        body = sys.stdin.read()
    refs = bare_body_refs(body)
    if refs:
        prefix = "::warning::" if os.environ.get("GITHUB_ACTIONS") else "WARNING: "
        print(prefix + "bare " + ", ".join("#" + r for r in refs)
              + " = code-repo PR; a tracker ticket needs %s#N" % TRACKER)
    reason = check(body)
    if reason:
        print("PR tracker link: FAIL — " + reason)
        return 1
    print("PR tracker link: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
