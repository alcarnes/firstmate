#!/usr/bin/env bash
# Post the single completion follow-up for an X-linked task and clear the link.
#
# An X mention that spawned real work is linked to its task by n1-x-link.sh
# (x_request/x_request_ts in state/<id>.meta). When that task reaches a terminal
# state (PR merged / survey report / local merge / failed), numberone composes a
# public-safe outcome and posts it here as ONE follow-up, within a 24h window.
# Past the window the relay would drop a late follow-up, so this skips silently
# and clears the link. A failed task still warrants an honest follow-up.
#
# Detection (no reply text needed - cheap pre-check before composing a reply):
#   n1-x-followup.sh --check <task-id>
#     exit 0, prints <request_id>  -> a follow-up is due (linked, within window)
#     exit 1, silent               -> not linked, or window elapsed (link pruned)
#
# Post (after composing the reply to a file or stdin):
#   n1-x-followup.sh <task-id> --text-file <path>
#   n1-x-followup.sh <task-id> -
#     Linked and within window: posts ONE follow-up via n1-x-reply.sh
#       --followup, clears the link on success, echoes <request_id>, exit 0.
#     Window elapsed: clears the link, posts nothing, exit 0 (silent skip).
#     Not linked: nothing to do, exit 0.
#     Failed post: leaves the link in place, exit non-zero, so it can be retried.
#
# Dry-run (FMX_DRY_RUN) flows through n1-x-reply.sh: the follow-up is recorded to
# state/x-outbox/<request_id>.json instead of posted, and the link is cleared
# exactly as a live post would, so the full loop runs end to end without a tweet.
#
# The 24h window is FMX_FOLLOWUP_MAX_AGE_SECS (default 86400). FMX_NOW_OVERRIDE
# pins "now" for deterministic tests. Meta read/write lives in n1-x-lib.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N1_ROOT="${N1_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
N1_HOME="${N1_HOME:-${N1_ROOT_OVERRIDE:-$N1_ROOT}}"
STATE="${N1_STATE_OVERRIDE:-$N1_HOME/state}"
# shellcheck source=bin/n1-x-lib.sh
. "$SCRIPT_DIR/n1-x-lib.sh"

usage() {
  echo "usage: n1-x-followup.sh --check <task-id> | <task-id> --text-file <path> | <task-id> -" >&2
}

MAX_AGE=${FMX_FOLLOWUP_MAX_AGE_SECS:-86400}
case "$MAX_AGE" in
  ''|*[!0-9]*) MAX_AGE=86400 ;;
esac

# Parse mode: --check is detection-only; otherwise it is a post, with the text
# source (--text-file <path> | -) deferred until after the link/window check so a
# missing link never consumes stdin or posts.
MODE=post
if [ "${1:-}" = --check ]; then
  MODE=check
  ID=${2:-}
  if [ -z "$ID" ] || [ "$#" -gt 2 ]; then usage; exit 2; fi
else
  ID=${1:-}
  if [ -z "$ID" ]; then usage; exit 2; fi
  shift
  TS_ARGS=("$@")
  if [ "${#TS_ARGS[@]}" -lt 1 ]; then usage; exit 2; fi
fi

case "$ID" in
  ''|.*|*[!A-Za-z0-9._-]*) echo "n1-x-followup: unsafe task id: $ID" >&2; exit 2 ;;
esac

META="$STATE/$ID.meta"
RID=$(fmx_meta_get "$META" x_request)
TS=$(fmx_meta_get "$META" x_request_ts)

# Not linked: this task did not originate from an X mention. Detection fails;
# a post is simply a no-op success (numberone need not special-case it).
if [ -z "$RID" ]; then
  if [ "$MODE" = check ]; then
    exit 1
  fi
  echo "n1-x-followup: $ID is not X-linked; nothing to post" >&2
  exit 0
fi

NOW=${FMX_NOW_OVERRIDE:-$(date +%s)}
case "$NOW" in
  ''|*[!0-9]*) echo "n1-x-followup: could not read the current time" >&2; exit 1 ;;
esac

# A missing or malformed timestamp cannot prove the follow-up is still in window,
# so treat it like an elapsed window: prune the link and skip.
EXPIRED=0
case "$TS" in
  ''|*[!0-9]*) EXPIRED=1 ;;
  *) [ "$((NOW - TS))" -gt "$MAX_AGE" ] && EXPIRED=1 ;;
esac

if [ "$EXPIRED" = 1 ]; then
  fmx_meta_link_clear "$META" || echo "n1-x-followup: warning: could not clear the elapsed link in state/$ID.meta" >&2
  if [ "$MODE" = check ]; then
    exit 1
  fi
  echo "n1-x-followup: follow-up window elapsed for $ID; skipped and cleared the link" >&2
  exit 0
fi

# Linked and within window.
if [ "$MODE" = check ]; then
  printf '%s\n' "$RID"
  exit 0
fi

# Post the follow-up. n1-x-reply owns text reading, thread-split, dry-run, the
# endpoint, and the never-inline safety; we only pass the text source through.
if "$N1_ROOT/bin/n1-x-reply.sh" "$RID" --followup "${TS_ARGS[@]}" >/dev/null; then
  fmx_meta_link_clear "$META" || echo "n1-x-followup: warning: posted but could not clear the link in state/$ID.meta" >&2
  printf '%s\n' "$RID"
  exit 0
fi

# Post failed: leave the link so numberone can retry on a later pass.
echo "n1-x-followup: follow-up post failed for $ID; left the link in place to retry" >&2
exit 1
