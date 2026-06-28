#!/usr/bin/env bash
# n1-marker-lib.sh - the from-numberone request marker.
#
# When the MAIN numberone relays a work request to one of its LIEUTENANTS,
# bin/n1-send.sh prepends this marker to the message text. A lieutenant is itself
# a numberone running in its own home, so without a marker it treats every
# incoming n1-send/tmux line as if its captain typed it and answers
# CONVERSATIONALLY in its own chat. But the main numberone never reads a
# lieutenant's chat: the only main<-lieutenant wakeup channel is the status file
# (charter escalation), optionally pointing to a doc for detail. A detailed
# chat-only reply therefore strands, unseen.
#
# The marker lets the lieutenant tell its supervisor's request apart from a
# message the captain typed directly into its pane:
#
#   - marked   -> a from-numberone request. Do the work, then respond via the
#                 STATUS/ESCALATION path (a status line for a terse result, or a
#                 doc plus a status pointer - the survey-report pattern - for a
#                 detailed one) so it surfaces to the main numberone via the
#                 watcher signal. It MUST NOT respond only in chat.
#   - unmarked -> the captain typing directly. Stay conversational, exactly as
#                 before: authoritative captain intervention.
#
# This contract lives in the generated lieutenant charter (bin/n1-brief.sh) so it
# travels with the live lieutenant, and is summarized in AGENTS.md.
#
# Distinct from the afk daemon marker, on purpose.
# The away-mode daemon (bin/n1-supervise-daemon.sh) marks its daemon->numberone
# escalations with a BARE leading unit separator (N1_INJECT_MARK, ASCII 0x1f).
# This from-numberone marker mirrors that CONCEPT - it reuses the ASCII unit
# separator (0x1f), which is untypable on a normal keyboard, as the "a human can
# never forge this" guarantee - but it is a DISTINCT sequence: a human-readable
# label FOLLOWED by the separator, never a bare leading 0x1f. The afk contract
# keys on a LEADING 0x1f, which this marker never has, so the two cannot
# conflate: a lieutenant's own afk machinery never mistakes a from-numberone
# request for an internal daemon escalation, and vice versa. The visible label is
# also what the lieutenant's LLM actually reads in its pane, since the separator
# byte itself is invisible.
#
# Sourced by bin/n1-send.sh, bin/n1-brief.sh, and the tests. No side effects on
# source. set -u / set -e safe.

# The label field: human-readable, greppable, and distinctive enough that the
# captain would not type it by hand. This is the part the lieutenant's LLM reads.
N1_FROMFIRST_LABEL='[n1-from-numberone]'

# The full marker n1-send prepends to a from-numberone request: the label, then
# the ASCII unit separator (0x1f) as the untypable field separator. The request
# text follows the separator.
N1_FROMFIRST_MARK="${N1_FROMFIRST_LABEL}"$'\x1f'

# fm_message_from_numberone: 0 (true) if <message> carries the from-numberone
# marker - it begins with the label immediately followed by the unit separator -
# and 1 otherwise. The unit separator is untypable, so a captain-typed message,
# even one that happens to start with the label text alone, is never matched.
fm_message_from_numberone() {  # <message>
  case "$1" in
    "$N1_FROMFIRST_MARK"*) return 0 ;;
  esac
  return 1
}
