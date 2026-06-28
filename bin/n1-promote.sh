#!/usr/bin/env bash
# Promote a survey task to a mission task in place: the ensign keeps its window,
# worktree, and loaded context; only the contract changes. Flips kind= to mission in
# state/<task-id>.meta so n1-teardown.sh applies the full mission-task teardown protection
# again. After promoting, send the ensign its mission instructions via n1-send.sh
# (inventory scratch state, reset to a clean default-branch base, carry over only
# intended fix changes, create branch fm/<task-id>, implement, then report done
# according to the project's delivery mode).
# Usage: n1-promote.sh <task-id>
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N1_ROOT="${N1_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
N1_HOME="${N1_HOME:-${N1_ROOT_OVERRIDE:-$N1_ROOT}}"
STATE="${N1_STATE_OVERRIDE:-$N1_HOME/state}"
"$N1_ROOT/bin/n1-guard.sh" || true
ID=$1
META="$STATE/$ID.meta"
[ -f "$META" ] || { echo "error: no meta for task $ID at $META" >&2; exit 1; }
grep -qx 'kind=survey' "$META" || { echo "error: task $ID is not a survey task (kind=survey not in meta)" >&2; exit 1; }

TMP="$META.tmp"
grep -v '^kind=' "$META" > "$TMP"
echo "kind=mission" >> "$TMP"
mv "$TMP" "$META"

echo "promoted $ID to mission (teardown protection restored)"
echo "next: bin/n1-send.sh n1-$ID '<mission instructions: review scratch state with git status and git log; reset to a clean default-branch base; carry over only intended fix changes; create branch fm/$ID; implement; report done>'"
