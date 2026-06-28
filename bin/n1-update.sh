#!/usr/bin/env bash
# Self-update a running numberone and its lieutenants to the latest origin.
#
# Mechanical half of the /updatenumberone skill. Fast-forwards the running
# numberone repo's default branch from origin, then fast-forwards every
# registered lieutenant home (each a treehouse worktree of this same repo, or
# a standalone clone) the same way. FAST-FORWARD ONLY, exactly like
# n1-fleet-sync.sh: never force, never create a merge commit, never stash;
# advance a target only when it is a clean fast-forward, otherwise skip and
# report. A tracked-files fast-forward never touches the gitignored operational
# dirs (data/, state/, config/, projects/, .no-mistakes/), so a lieutenant's
# in-flight work is never disrupted. Worktrees of this repo share one object
# store, so a single fetch refreshes them all; standalone-clone homes are
# fetched on their own. Lieutenant homes are leased at a detached HEAD on the
# default branch, so a fast-forward there advances HEAD only and never touches
# any other worktree's checkout or the shared `main` branch.
#
# The fast-forward mechanics live in bin/n1-ff-lib.sh (base_mode "origin" here);
# the same library drives the local-HEAD lieutenant sync used by n1-spawn.sh and
# n1-bootstrap.sh, so there is one ff implementation, not several.
#
# It does NOT re-read AGENTS.md or nudge lieutenants itself - those are LLM /
# tmux actions the skill performs. The script's job is the safe git mechanics
# plus a parseable summary telling the caller what to do next:
#   - one status line per target (updated/already current/skipped)
#   - reread-numberone: yes|no    (did the running numberone's instructions change)
#   - nudge-lieutenants: <window-targets...>|none   (updated live lieutenants to nudge)
#
# Usage: n1-update.sh [--help]
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N1_ROOT="${N1_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
N1_HOME="${N1_HOME:-${N1_ROOT_OVERRIDE:-$N1_ROOT}}"
STATE="${N1_STATE_OVERRIDE:-$N1_HOME/state}"
LIEUTENANTS_MD="$N1_HOME/data/lieutenants.md"
# shellcheck source=bin/n1-ff-lib.sh
. "$SCRIPT_DIR/n1-ff-lib.sh"

"$SCRIPT_DIR/n1-guard.sh" || true

usage() { echo "usage: n1-update.sh [--help]" >&2; }

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi
[ $# -eq 0 ] || { usage; exit 1; }

# --- main numberone repo ---------------------------------------------------

reread_numberone="no"
ff_target "$N1_ROOT" "numberone" origin no no
if [ "$FF_STATUS" = "updated" ] && [ -n "$FF_INSTR" ]; then
  reread_numberone="yes"
fi

# --- lieutenants -----------------------------------------------------------
# An updated live lieutenant is nudged whenever it advanced (nudge_requires_instr
# is "no" here): /updatenumberone's nudge is a gentle re-read steer, kept on the
# same condition it has always used.

FF_NUDGE_WINDOWS=""
FF_SEEN_HOMES=""

# Live direct reports first: state/<id>.meta with kind=lieutenant carries the
# authoritative home= path.
sweep_live_lieutenant_metas "$STATE" origin no

# Registry backstop: a lieutenant registered in data/lieutenants.md but without
# a live meta (e.g. between restarts) is still its persistent on-disk home.
if [ -f "$LIEUTENANTS_MD" ]; then
  while IFS= read -r line; do
    case "$line" in
      "- "*) ;;
      *) continue ;;
    esac
    id=$(printf '%s\n' "$line" | sed -n 's/^- \([^ ][^ ]*\) - .*/\1/p')
    home=$(printf '%s\n' "$line" | sed -n 's/.*(home:[[:space:]]*\([^;]*\);.*/\1/p' | sed 's/[[:space:]]*$//')
    process_lieutenant "$id" "$home" "" origin no
  done < "$LIEUTENANTS_MD"
fi

# --- caller action summary -------------------------------------------------

echo "reread-numberone: $reread_numberone"
echo "nudge-lieutenants:${FF_NUDGE_WINDOWS:- none}"
