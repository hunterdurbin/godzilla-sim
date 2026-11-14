#!/usr/bin/env python3
"""Warn on bare `#N` references in a commit message (githooks/commit-msg).

In this repo a bare `#N` means a code-repo PR (GitHub's squash merge also
appends `(#PR)` to the subject); a tracker ticket needs the full
`hunterdurbin/godzilla-sim-issue-tracker#N` (docs/agents/issue-tracker.md
§ Referencing code). Warns only — a bare `#N` that means a code PR is fine.

Usage: check_commit_msg_refs.py <commit-msg-file>   (always exits 0)
       check_commit_msg_refs.py --self-test
"""
import re
import sys

# `#N` not glued to a word/path before it (owner/repo#N is qualified).
BARE_REF = re.compile(r"(?<![\w./-])#(\d+)\b")


def bare_refs(message: str) -> list:
    refs = []
    for line in message.splitlines():
        if line.startswith("#"):  # git's comment lines
            continue
        refs.extend(BARE_REF.findall(line))
    return refs


def self_test() -> None:
    assert bare_refs("Fix advance (#19)") == ["19"]
    assert bare_refs("Part of hunterdurbin/godzilla-sim-issue-tracker#19.") == []
    assert bare_refs("See hunterdurbin/godzilla-sim#240") == []
    assert bare_refs("# Please enter the commit message #5") == []
    assert bare_refs("color #fff and issue#3") == []
    print("check_commit_msg_refs: self-test OK")


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return 0
    with open(sys.argv[1], encoding="utf-8") as f:
        refs = bare_refs(f.read())
    if refs:
        print("commit-msg: bare " + ", ".join("#" + r for r in refs)
              + " = code-repo PR. A tracker ticket needs "
              "hunterdurbin/godzilla-sim-issue-tracker#N "
              "(docs/agents/issue-tracker.md); amend if that was meant.",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
