#!/usr/bin/env bash
# Send one line of literal text to a ensign window, then Enter.
# Usage: n1-send.sh <window> <text...>
#   <window> may be a bare numberone window name (n1-xyz), resolved through
#   this home's state/<id>.meta, or explicit session:window.
# Special keys instead of text: n1-send.sh <window> --key Escape   (or Enter, C-c, ...)
#
# Text submission is verified: the line is typed ONCE, then Enter is sent and
# retried (Enter only, never retyped) until the composer clears. If a swallowed
# Enter is positively confirmed (the text is still sitting in the composer after
# all retries), n1-send exits NON-ZERO so the caller knows the steer did not land
# instead of silently leaving an unsubmitted instruction (incident afk-invx-i5).
# The composer/submit logic is shared with the away-mode daemon via
# bin/n1-tmux-lib.sh. Tune with N1_SEND_RETRIES (default 3) / N1_SEND_SLEEP (0.4).
# Slash commands, and codex `$...` skill invocations resolved through harness
# meta, get a longer pre-Enter settle so completion popups do not swallow Enter.
#
# From-numberone marker: when the resolved target is a bare `n1-<id>` whose meta
# records kind=lieutenant, the text is prefixed with the from-numberone marker
# (bin/n1-marker-lib.sh) so the lieutenant routes its reply via its status file
# or a status-pointed doc instead of stranding it in chat the main numberone
# never reads. A ensign/survey target, an explicit session:window escape-hatch
# target, and the --key path are never marked - their behavior is unchanged.
# After a successful text submit n1-send pauses N1_SEND_SETTLE seconds (default 1,
# 0 disables) before returning: a cleared composer only proves the text was
# submitted, but the harness needs a beat to spin up the turn before its busy
# footer appears, so an immediate peek would otherwise see the stale idle pane.
# The pause is n1-send-only; the shared submit core (used by the away-mode daemon,
# which only needs "submitted") does not pay it, and the --key path is unaffected.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N1_ROOT="${N1_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
N1_HOME="${N1_HOME:-${N1_ROOT_OVERRIDE:-$N1_ROOT}}"
STATE="${N1_STATE_OVERRIDE:-$N1_HOME/state}"

# shellcheck source=bin/n1-tmux-lib.sh
. "$SCRIPT_DIR/n1-tmux-lib.sh"
# shellcheck source=bin/n1-marker-lib.sh
. "$SCRIPT_DIR/n1-marker-lib.sh"

"$SCRIPT_DIR/n1-guard.sh" || true

resolve() {
  case "$1" in
    *:*) echo "$1" ;;
    n1-*)
      meta="$STATE/${1#n1-}.meta"
      if [ ! -f "$meta" ]; then
        echo "error: no metadata for $1 in $STATE; pass session:window to target a window outside this numberone home" >&2
        exit 1
      fi
      window=$(grep '^window=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
      [ -n "$window" ] || { echo "error: no window recorded in $meta" >&2; exit 1; }
      echo "$window"
      ;;
    *) tmux list-windows -a -F '#{session_name}:#{window_name}' | grep -m1 ":$1\$" \
         || { echo "error: no window named $1" >&2; exit 1; } ;;
  esac
}

RAW_TARGET=$1
T=$(resolve "$1")
shift

# Mark a from-numberone -> lieutenant request. Only a bare `n1-<id>` target,
# resolved through this home's meta and recording kind=lieutenant, is marked: the
# lieutenant then routes its reply via the status path (see n1-marker-lib.sh).
# An explicit session:window target (the escape hatch for windows outside this
# home) and any ensign/survey target are left unmarked, and so is the --key path.
MARK_PREFIX=""
case "$RAW_TARGET" in
  n1-*)
    meta="$STATE/${RAW_TARGET#n1-}.meta"
    if [ -f "$meta" ] && grep -q '^kind=lieutenant$' "$meta" 2>/dev/null; then
      MARK_PREFIX="$N1_FROMFIRST_MARK"
    fi
    ;;
esac

# Resolve the target's harness from its meta (recorded by n1-spawn), used only to
# scope the codex `$<skill>` popup-settle below. A bare n1-<id> target carries
# meta; an explicit session:window escape-hatch target has none, so its harness is
# unknown and treated as non-codex (the safe default that keeps the fast path).
TARGET_HARNESS=""
case "$RAW_TARGET" in
  n1-*)
    meta="$STATE/${RAW_TARGET#n1-}.meta"
    if [ -f "$meta" ]; then
      TARGET_HARNESS=$(grep '^harness=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    fi
    ;;
esac

if [ "${1:-}" = "--key" ]; then
  tmux send-keys -t "$T" "$2"
else
  # Slash commands open a completion popup in some TUIs (verified on codex);
  # submitting too fast selects nothing, so give the popup time to settle before
  # the (retried) Enter. Codex opens the same kind of popup for a `$<skill>`
  # invocation, so a `$...` message to a codex target gets the same settle. That
  # `$` case is scoped to codex on purpose: unlike `/`, a leading `$` commonly
  # starts ordinary text ("$5/month", "$HOME"), so a universal `$` rule would
  # needlessly slow plain text to claude/opencode/pi. The retried Enter in
  # fm_tmux_submit_core still backs the settle up either way.
  case "$*" in
    /*) settle=1.2 ;;
    \$*)
      if [ "$TARGET_HARNESS" = codex ]; then settle=1.2; else settle=0.3; fi
      ;;
    *) settle=0.3 ;;
  esac
  retries=${N1_SEND_RETRIES:-3}
  sleep_s=${N1_SEND_SLEEP:-0.4}
  # Type once, submit, verify. Lenient: only a positively-confirmed swallow
  # (text still in the composer) is an error; an unreadable pane is assumed sent.
  verdict=$(fm_tmux_submit_core "$T" "$MARK_PREFIX$*" "$retries" "$sleep_s" "$settle")
  case "$verdict" in
    pending)
      echo "error: text not submitted to $T (Enter swallowed; text left in composer)" >&2
      exit 1
      ;;
    send-failed)
      echo "error: text not sent to $T (tmux send-keys failed)" >&2
      exit 1
      ;;
  esac
  # Submit landed (verdict was not pending/send-failed). The cleared composer only
  # proves the text was submitted; the harness still needs a beat to spin up the
  # turn before its busy footer shows. Pause so an immediate peek catches the
  # ensign actually working instead of the stale idle pane. N1_SEND_SETTLE=0
  # disables it. Scoped to this path only, never the shared submit core.
  [ "${N1_SEND_SETTLE:-1}" = 0 ] || sleep "${N1_SEND_SETTLE:-1}"
fi
