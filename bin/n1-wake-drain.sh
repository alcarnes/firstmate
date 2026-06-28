#!/usr/bin/env bash
# Atomically drain durable watcher wake records, then assert watcher liveness.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/n1-wake-lib.sh
. "$SCRIPT_DIR/n1-wake-lib.sh"

DRAIN_TMP=
DRAIN_LOCK_HELD=false

# Defense in depth for the watcher re-arm chain: this script runs at the top of
# every wake-handling and recovery turn, so assert watcher liveness here too. A
# lapsed supervision chain then surfaces on a plain drain-and-handle turn, not
# only when a guarded supervision script (n1-peek/n1-send/...) happens to run.
# Reuse n1-guard.sh's existing graced, beacon-based banner (N1_GUARD_GRACE) - do
# not duplicate the beacon math. Because the watcher touches its beacon every
# poll cycle, a normal fire leaves a recent beacon well inside grace and stays
# silent; only a genuine stale-beyond-grace lapse with work in flight warns. Call
# after the queue is emptied so guard never re-prints its own queued-wakes notice
# for the records this run just drained, and never let a guard hiccup change the
# drain's exit status.
assert_watcher_liveness() {
  "$SCRIPT_DIR/n1-guard.sh" || true
}

# shellcheck disable=SC2317,SC2329 # Invoked by trap handlers below.
cleanup() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$DRAIN_LOCK_HELD" = true ] && [ -n "$DRAIN_TMP" ] && [ -e "$DRAIN_TMP" ]; then
    fm_wake_restore_queue "$DRAIN_TMP" || true
  fi
  if [ "$DRAIN_LOCK_HELD" = true ]; then
    fm_lock_release "$N1_WAKE_QUEUE_LOCK"
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fm_lock_acquire_wait "$N1_WAKE_QUEUE_LOCK"
DRAIN_LOCK_HELD=true

if [ ! -s "$N1_WAKE_QUEUE" ]; then
  : > "$N1_WAKE_QUEUE"
  assert_watcher_liveness
  exit 0
fi

DRAIN_TMP="$STATE/.wake-queue.drain.$(fm_current_pid)"
rm -f "$DRAIN_TMP"
mv "$N1_WAKE_QUEUE" "$DRAIN_TMP" || exit 1
: > "$N1_WAKE_QUEUE" || exit 1

fm_wake_print_deduped "$DRAIN_TMP" || exit "$?"
rm -f "$DRAIN_TMP"
DRAIN_TMP=
assert_watcher_liveness
exit 0
