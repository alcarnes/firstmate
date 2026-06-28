#!/usr/bin/env bash
# n1-send from-numberone marker for lieutenant targets.
#
# A lieutenant is itself a numberone, so a request relayed to it lands in its own
# chat - which the main numberone never reads (the only channel back is the terse
# status file). n1-send therefore prepends a from-numberone marker
# (bin/n1-marker-lib.sh) when, and only when, the resolved target is a bare
# `n1-<id>` whose meta records kind=lieutenant, so the lieutenant can recognize
# the request and route its reply via the status path. These tests pin that
# behavior hermetically (stubbed tmux, no real agent):
#   1. A send to a kind=lieutenant target prepends the marker to the literal text.
#   2. A send to a ensign (kind=mission) target sends the bare text, no marker.
#   3. An explicit session:window target (no meta) is never marked.
#   4. The --key path never carries the marker.
#   5. The marker is exactly the label "[n1-from-numberone]" + ASCII 0x1f, and the
#      fm_message_from_numberone detector keys on that untypable sequence.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/n1-marker-lib.sh
. "$ROOT/bin/n1-marker-lib.sh"

SEND="$ROOT/bin/n1-send.sh"

TMP_ROOT=$(fm_test_tmproot n1-send-marker)

# A fake tmux that (a) records the literal text of every `send-keys -l` to
# N1_SEND_LOG and (b) lets n1-send's submit path reach a clean "empty" verdict.
# display-message yields a numeric cursor_y; capture-pane returns an empty
# bordered composer so fm_tmux_composer_state reads "empty" (submit landed) on the
# first Enter. Only the literal (-l) text is logged; Enter retries and --key sends
# are not, so the log holds exactly what was typed into the composer.
make_stubs() {  # <dir> -> echoes fakebin dir
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  send-keys)
    shift
    literal=0
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) shift 2 ;;
        -l) literal=1; shift ;;
        *) break ;;
      esac
    done
    if [ "$literal" = 1 ]; then
      printf '%s' "${1:-}" >> "$N1_SEND_LOG"
    fi
    exit 0 ;;
  display-message)
    for a in "$@"; do case "$a" in *cursor_y*) printf '0\n'; exit 0 ;; esac; done
    printf 'fakepane\n'; exit 0 ;;
  capture-pane) printf '\xe2\x94\x82 \xe2\x94\x82\n'; exit 0 ;;
  list-windows) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fb/tmux"
  cat > "$fb/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fb/sleep"
  printf '%s\n' "$fb"
}

# run_send <fakebin> <home> <send-log> -- <n1-send args...>
# Runs n1-send.sh with the stubs on PATH against the given home (which holds
# state/<id>.meta). N1_ROOT_OVERRIDE points at the same non-repo home so
# n1-guard's tangle check stays silent; guard noise goes to stderr (discarded).
# N1_SEND_SETTLE=0 keeps the run fast. Truncates the log first; returns n1-send's
# exit code.
run_send() {
  local fb=$1 home=$2 log=$3; shift 3
  : > "$log"
  env PATH="$fb:$PATH" \
    N1_ROOT_OVERRIDE="$home" N1_HOME="$home" N1_SEND_LOG="$log" N1_SEND_SETTLE=0 \
    "$SEND" "$@" 2>/dev/null
}

# setup_home <name> -> echoes a fresh home dir with an empty state/.
setup_home() {
  local home="$TMP_ROOT/$1-$RANDOM"
  mkdir -p "$home/state"
  printf '%s\n' "$home"
}

test_lieutenant_target_is_marked() {
  local dir fb log home rc got
  dir="$TMP_ROOT/sm"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); log="$dir/send.log"
  home=$(setup_home sm)
  fm_write_lieutenant_meta "$home/state/domain.meta" "$home" "sess:n1-domain"
  run_send "$fb" "$home" "$log" "n1-domain" "audit the build"; rc=$?
  expect_code 0 "$rc" "send to a lieutenant target should succeed"
  got=$(cat "$log")
  case "$got" in
    "$N1_FROMFIRST_MARK"audit\ the\ build) : ;;
    *) fail "lieutenant send: literal text should be marker+text"$'\n'"--- bytes ---"$'\n'"$(printf '%s' "$got" | od -An -c)" ;;
  esac
  pass "n1-send: a kind=lieutenant target gets the from-numberone marker prepended"
}

test_ensign_target_is_not_marked() {
  local dir fb log home rc got
  dir="$TMP_ROOT/crew"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); log="$dir/send.log"
  home=$(setup_home crew)
  fm_write_meta "$home/state/build.meta" \
    "window=sess:n1-build" "worktree=$home/wt" "project=$home/p" \
    "harness=echo" "kind=mission" "mode=no-mistakes" "yolo=off"
  run_send "$fb" "$home" "$log" "n1-build" "fix the test"; rc=$?
  expect_code 0 "$rc" "send to a ensign target should succeed"
  got=$(cat "$log")
  [ "$got" = "fix the test" ] \
    || fail "ensign send: expected bare text, got marker or other"$'\n'"--- bytes ---"$'\n'"$(printf '%s' "$got" | od -An -c)"
  pass "n1-send: a kind=mission (ensign) target is sent unmarked"
}

test_explicit_window_is_not_marked() {
  local dir fb log home rc got
  dir="$TMP_ROOT/explicit"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); log="$dir/send.log"
  home=$(setup_home explicit)
  # No meta lookup happens for an explicit session:window target, so even with a
  # same-named lieutenant meta present it must stay unmarked (escape hatch).
  fm_write_lieutenant_meta "$home/state/win.meta" "$home" "other:win"
  run_send "$fb" "$home" "$log" "other:win" "ping"; rc=$?
  expect_code 0 "$rc" "send to an explicit window should succeed"
  got=$(cat "$log")
  [ "$got" = "ping" ] \
    || fail "explicit session:window send: expected bare text, got marker"$'\n'"--- bytes ---"$'\n'"$(printf '%s' "$got" | od -An -c)"
  pass "n1-send: an explicit session:window target is never marked"
}

test_key_path_is_not_marked() {
  local dir fb log home rc
  dir="$TMP_ROOT/key"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); log="$dir/send.log"
  home=$(setup_home key)
  fm_write_lieutenant_meta "$home/state/domain.meta" "$home" "sess:n1-domain"
  run_send "$fb" "$home" "$log" "n1-domain" --key Escape; rc=$?
  expect_code 0 "$rc" "--key send to a lieutenant should succeed"
  [ ! -s "$log" ] \
    || fail "--key path logged a literal send (marker leaked into a keypress)"$'\n'"--- bytes ---"$'\n'"$(od -An -c "$log")"
  pass "n1-send: the --key path carries no marker (no literal text is typed)"
}

test_marker_is_label_plus_unit_separator() {
  local us hex
  us=$(printf '\037')
  [ "$N1_FROMFIRST_MARK" = "[n1-from-numberone]$us" ] \
    || fail "marker is not the expected label + 0x1f sequence"$'\n'"--- bytes ---"$'\n'"$(printf '%s' "$N1_FROMFIRST_MARK" | od -An -c)"
  # The last byte must be ASCII unit separator 0x1f, the untypable guarantee.
  hex=$(printf '%s' "$N1_FROMFIRST_MARK" | od -An -tx1 | tr -d ' \n')
  case "$hex" in
    *1f) : ;;
    *) fail "marker does not end in a 0x1f byte; bytes were: $hex" ;;
  esac
  # The detector keys on that exact untypable sequence.
  fm_message_from_numberone "${N1_FROMFIRST_MARK}do the work" \
    || fail "detector should recognize a marked message"
  fm_message_from_numberone "do the work" \
    && fail "detector must reject an unmarked message"
  # The bare label without the separator (the typable part) is NOT a match.
  fm_message_from_numberone "[n1-from-numberone]do the work" \
    && fail "detector must reject the label without the 0x1f separator"
  pass "n1-send: the marker is exactly '[n1-from-numberone]' + ASCII 0x1f, detector keys on it"
}

test_lieutenant_target_is_marked
test_ensign_target_is_not_marked
test_explicit_window_is_not_marked
test_key_path_is_not_marked
test_marker_is_label_plus_unit_separator
