#!/usr/bin/env bash
# tests/lieutenant-helpers.sh - shared fixtures and mocks for the lieutenant
# suites (n1-lieutenant-lifecycle-e2e and n1-lieutenant-safety).
#
# These mocks encode lieutenant-lifecycle behavior (fake tmux that logs window
# ops, fake treehouse that leases/returns homes, fake no-mistakes that records
# init/doctor), so they live here rather than in the generic tests/lib.sh. The
# generic git/identity/meta primitives come from lib.sh, which this file pulls in.

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# A fake tmux (window ops are logged to N1_FAKE_TMUX_LOG, list-windows returns
# N1_FAKE_TMUX_WINDOW, capture-pane echoes N1_FAKE_TMUX_CAPTURE) plus a fake
# treehouse (durable lease of N1_FAKE_TREEHOUSE_HOME, recording the lease holder
# to N1_FAKE_TREEHOUSE_LEASE_FILE; `return` removes the target and lease unless
# N1_FAKE_TREEHOUSE_RETURN_FAIL is set). Echoes the fakebin dir.
make_fake_tmux() {
  local dir=$1 fakebin capture
  fakebin=$(fm_fakebin "$dir")
  capture="$dir/pane.txt"
  printf 'idle prompt\n' > "$capture"
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  has-session|new-session|new-window|send-keys|kill-window)
    printf '%s\n' "$*" >> "$N1_FAKE_TMUX_LOG"
    exit 0
    ;;
  list-windows)
    if [ -n "${N1_FAKE_TMUX_WINDOW:-}" ]; then
      printf '%s\n' "$N1_FAKE_TMUX_WINDOW"
    fi
    exit 0
    ;;
  display-message)
    printf 'numberone\n'
    exit 0
    ;;
  capture-pane)
    printf '%s\n' "$*" >> "$N1_FAKE_TMUX_LOG"
    cat "$N1_FAKE_TMUX_CAPTURE"
    exit 0
    ;;
esac
exit 1
SH
  cat > "$fakebin/treehouse" <<'SH'
#!/usr/bin/env bash
set -u
printf 'treehouse %s\n' "$*" >> "${N1_FAKE_TMUX_LOG:-/dev/null}"
case "${1:-}" in
  get)
    # Durable lease: print only the worktree path to stdout (banners to stderr),
    # and record the lease holder so tests can assert it is set and later cleared.
    shift
    holder=
    while [ $# -gt 0 ]; do
      case "$1" in
        --lease) ;;
        --lease-holder) shift; holder=${1:-} ;;
        --lease-holder=*) holder=${1#--lease-holder=} ;;
      esac
      shift
    done
    if [ -n "${N1_FAKE_TREEHOUSE_HOME:-}" ]; then
      mkdir -p "$N1_FAKE_TREEHOUSE_HOME"
      [ -n "${N1_FAKE_TREEHOUSE_LEASE_FILE:-}" ] && printf '%s\n' "$holder" > "$N1_FAKE_TREEHOUSE_LEASE_FILE"
      printf 'leased worktree for %s\n' "${holder:-unknown}" >&2
      printf '%s\n' "$N1_FAKE_TREEHOUSE_HOME"
    fi
    exit 0
    ;;
  return)
    shift
    target=
    while [ $# -gt 0 ]; do
      case "$1" in
        --force) ;;
        *) target=$1 ;;
      esac
      shift
    done
    [ -z "${N1_FAKE_TREEHOUSE_RETURN_FAIL:-}" ] || exit 17
    [ -n "${N1_FAKE_TREEHOUSE_LEASE_FILE:-}" ] && rm -f "$N1_FAKE_TREEHOUSE_LEASE_FILE"
    [ -n "$target" ] && rm -rf -- "$target"
    exit 0
    ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  chmod +x "$fakebin/treehouse"
  : > "$dir/tmux.log"
  printf '%s\n' "$fakebin"
}

# A fake no-mistakes that touches .no-mistakes-init / .no-mistakes-doctor markers.
make_fake_no_mistakes() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -eu
case "${1:-}" in
  init) touch .no-mistakes-init ;;
  doctor) touch .no-mistakes-doctor ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$fakebin/no-mistakes"
  printf '%s\n' "$fakebin"
}

# A fake no-mistakes that records each "<pwd>\t<verb>" call to
# N1_FAKE_NO_MISTAKES_LOG and fails for the project named N1_FAKE_NO_MISTAKES_FAIL_PROJECT.
make_recording_no_mistakes() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\t%s\n' "$PWD" "${1:-}" >> "$N1_FAKE_NO_MISTAKES_LOG"
if [ "$(basename "$PWD")" = "${N1_FAKE_NO_MISTAKES_FAIL_PROJECT:-}" ]; then
  exit 1
fi
case "${1:-}" in
  init) touch .no-mistakes-init ;;
  doctor) touch .no-mistakes-doctor ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$fakebin/no-mistakes"
  printf '%s\n' "$fakebin"
}

# Make a directory look like a minimal numberone home (AGENTS.md + bin/).
mark_numberone_home() {
  local home=$1
  mkdir -p "$home/bin"
  printf '# Number One\n' > "$home/AGENTS.md"
}

# A numberone home that is also a real git repo (so it can host detached
# worktrees for teardown/lease tests).
make_numberone_git_root() {
  local home=$1
  mkdir -p "$home/bin"
  printf '# Number One\n' > "$home/AGENTS.md"
  cat > "$home/bin/n1-guard.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$home/bin/n1-guard.sh"
  git -C "$home" init -q
  git -C "$home" add AGENTS.md bin/n1-guard.sh
  git -C "$home" -c user.name='Number One Tests' -c user.email='tests@example.invalid' commit -qm initial
}

# Scaffold a filled lieutenant charter brief under <home>/data/<id>/brief.md.
# Args: home id charter [project...]
scaffold_lieutenant_charter() {
  local home=$1 id=$2 charter=$3
  shift 3
  N1_HOME="$home" N1_LIEUTENANT_CHARTER="$charter" "$ROOT/bin/n1-brief.sh" "$id" --lieutenant "$@" >/dev/null
}

# Make a directory look like a genuine seeded lieutenant home (for handoff tests).
seed_lieutenant_home_marker() {
  local home=$1 id=$2
  mark_numberone_home "$home"
  mkdir -p "$home/data"
  printf '%s\n' "$id" > "$home/.n1-lieutenant-home"
}

# Wait up to <limit> 0.1s ticks while <pid> stays alive. Returns 1 if it dies.
wait_live() {
  local pid=$1 limit=${2:-30} i=0
  while [ "$i" -lt "$limit" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
    sleep 0.1
    i=$((i + 1))
  done
  return 0
}
