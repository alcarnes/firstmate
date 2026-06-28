#!/usr/bin/env bash
# Link a spawned task to the X mention that triggered it, so numberone can post
# ONE completion follow-up reply when the task lands (within a 24h window).
#
# Usage: n1-x-link.sh <task-id> <request_id>
#
# Records two lines in state/<task-id>.meta (replacing any prior link, preserving
# every other meta line):
#   x_request=<request_id>     the relay-issued id the follow-up posts against
#   x_request_ts=<epoch>       link time, for the 24h follow-up window
#
# This is a separate step the fmx-respond skill runs AFTER n1-spawn.sh, so it
# never changes n1-spawn's interface. The follow-up itself - detection, the
# window check, the post, and clearing the link - is owned by n1-x-followup.sh on
# the task's terminal-completion wake. The meta read/write lives in n1-x-lib.sh.
#
# Both ids are relay/numberone slugs that compose a filename, so they are guarded
# against path traversal even though they come from trusted callers.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N1_ROOT="${N1_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
N1_HOME="${N1_HOME:-${N1_ROOT_OVERRIDE:-$N1_ROOT}}"
STATE="${N1_STATE_OVERRIDE:-$N1_HOME/state}"
# shellcheck source=bin/n1-x-lib.sh
. "$SCRIPT_DIR/n1-x-lib.sh"

ID=${1:-}
RID=${2:-}
if [ -z "$ID" ] || [ -z "$RID" ]; then
  echo "usage: n1-x-link.sh <task-id> <request_id>" >&2
  exit 2
fi

# task-id composes a path (state/<id>.meta); request_id composes a path elsewhere
# (the inbox/outbox record). Reject anything outside a safe slug for both.
case "$ID" in
  ''|.*|*[!A-Za-z0-9._-]*) echo "n1-x-link: unsafe task id: $ID" >&2; exit 2 ;;
esac
case "$RID" in
  ''|.*|*[!A-Za-z0-9._-]*) echo "n1-x-link: unsafe request_id: $RID" >&2; exit 2 ;;
esac

META="$STATE/$ID.meta"
if [ ! -f "$META" ]; then
  echo "n1-x-link: no such task: state/$ID.meta" >&2
  exit 1
fi

# FMX_NOW_OVERRIDE keeps tests deterministic; production uses the wall clock.
NOW=${FMX_NOW_OVERRIDE:-$(date +%s)}
case "$NOW" in
  ''|*[!0-9]*) echo "n1-x-link: could not read the current time" >&2; exit 1 ;;
esac

if ! fmx_meta_link_set "$META" "$RID" "$NOW"; then
  echo "n1-x-link: failed to record the link in state/$ID.meta" >&2
  exit 1
fi

printf 'linked %s to X request %s\n' "$ID" "$RID"
