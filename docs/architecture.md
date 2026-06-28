# Architecture

How numberone works, in depth.

The [README](../README.md) carries the high-level diagram and a short synopsis.
This document expands every part of it.
numberone's full operating manual for the orchestrator agent itself is [`AGENTS.md`](../AGENTS.md); this is the human-facing companion.

## Event-driven supervision

A zero-token bash watcher (`bin/n1-watch.sh`) sleeps on the fleet, classifies detected wakes in bash, and wakes the Number One only when something is actionable.
Actionable wakes include captain-relevant status signals, check-script output such as PR merge polling or an X mention, terminal stale panes, non-terminal stale panes that persist past `N1_STALE_ESCALATE_SECS`, and heartbeat backstop hits.
Those actionable wakes are written to a durable local queue (`state/.wake-queue`) before detector state advances, so a missed process exit can be recovered by draining the queue.
Benign wakes, such as `working:` notes, bare turn-ended signals, fresh non-terminal stale panes, and no-change heartbeats, advance their suppression markers, log to `state/.watch-triage.log`, and keep the watcher blocking without a queue record or LLM turn.
After each drain, `n1-wake-drain.sh` runs the same liveness guard as the supervision scripts, so a lapsed watcher chain surfaces even on a turn that only drains and handles queued wakes.
Routine watcher polling, re-arm no-ops, elapsed waiting time, and absorbed benign wakes stay silent; an idle crew costs you nothing.
Crew status files are append-only wake-event logs, not current-state fields.
`bin/n1-crew-state.sh <id>` is the cheap current-state read for an actionable heartbeat review: it attributes the matching no-mistakes run, active or terminal, to the crew's own branch and keeps that run-step authoritative even if the pane has closed.
Only when no matching run exists does it fall back to the pane busy-signature and then the status log; a dead pane without a run reports unknown instead of trusting a stale log.
Optional X mode rides the same check path: bootstrap drops a local `state/x-watch.check.sh` shim only after the user opts in with `FMX_PAIRING_TOKEN`, and non-X homes keep the default watcher behavior.

Routine re-arms go through `bin/n1-watch-arm.sh`, which forks the watcher as a tracked child, verifies it is genuinely alive with a fresh liveness beacon, and prints exactly one honest status line (`started` / `healthy` / `FAILED`, the last exiting non-zero) - never a false `already running` off a dying process.
Its `--restart` mode signals only the watcher recorded in the current home's `state/.watch.lock`, so restarting one home cannot kill sibling lieutenant watchers.
A pull-based guard (`bin/n1-guard.sh`) warns through supervision tool output if the primary checkout is tangled, or if tasks are in flight and that watcher stops running or queued wakes are waiting to be drained.
The drain script calls that guard after emptying the queue, which avoids repeating the queued-wakes warning for records it just consumed while still warning on stale watcher liveness.
It leads with prominent bordered banners for the tangle and no-watcher cases so they cannot be skimmed past.

A presence-gated sub-supervisor (`bin/n1-supervise-daemon.sh`) extends this for walk-away supervision: the `/afk` skill activates it, after which the watcher reverts to daemon-managed one-shot mode and the daemon self-handles routine wakes in bash.
The watcher and daemon share `bin/n1-classify-lib.sh`, so captain-relevant status verbs and signal, stale, and heartbeat-scan classification stay consistent in both modes.
The daemon escalates only captain-relevant events as one batched, single-line digest (prefixed with an in-band sentinel marker so numberone can tell daemon injections apart from real messages).
Its injection path shares `bin/n1-tmux-lib.sh` with `n1-send.sh`, so dim-ghost-aware and border-aware composer detection plus verified submit retry stay consistent; stalled escalation delivery raises `state/.subsuper-inject-wedged` after `N1_MAX_DEFER_SECS` instead of silently deferring forever.
`n1-send.sh` selects a pre-Enter popup-settle for slash commands and for codex `$...` skill invocations using the target's recorded `harness=` meta, then adds its own `N1_SEND_SETTLE` pause after successful text sends so immediate peeks catch the receiving turn starting; the sub-supervisor uses only the shared submit core and does not pay that post-submit pause.

## Worktrees, not branches in your checkout

Ensigns never intentionally touch your project clone; [treehouse](https://github.com/kunchenguid/treehouse) pools clean worktrees so parallel tasks on one repo cannot collide.
For mission and survey work, `n1-spawn.sh` waits for `treehouse get` and then refuses to launch unless the pane resolves to a real git worktree root that is distinct from the project primary checkout.

The numberone repo has one extra exposure because it can dispatch ensigns to work on itself.
Its operating checkout (`N1_ROOT`) and the disposable ensign worktrees are all linked git worktrees of the same repository, so the valid discriminator is branch state, not whether the checkout is linked.
The primary checkout is healthy on its default branch, and linked worktrees or lieutenant homes are healthy at detached HEAD.
Only a named non-default branch checked out in `N1_ROOT` is a worktree tangle.

`n1-tangle-lib.sh` resolves the default branch from `origin/HEAD`, then local `main` or `master`, and classifies that named non-default primary branch as the tangle.
`n1-guard.sh` prints the repair command on the next fleet action, while `n1-bootstrap.sh` reports the same condition as a `TANGLE:` line at session start.
Mission briefs also tell the ensign to verify `pwd -P` and `git rev-parse --show-toplevel` before creating `fm/<id>`, then stop with a blocked status if it landed in the primary checkout.

## Two task shapes

Mission tasks change projects and mission by project mode (`no-mistakes`, `direct-PR`, or `local-only`); survey tasks investigate, plan, reproduce bugs, or audit, then leave a report at `data/<id>/report.md` and never push.

## Optional lieutenants

`data/lieutenants.md` records persistent domain supervisors with natural-language scopes, project clone lists, and home paths.
`n1-home-seed.sh` provisions the isolated home, clones the listed PR-based projects into it, initializes newly cloned `no-mistakes` projects, copies the charter to `data/charter.md`, and `n1-spawn.sh --lieutenant` launches it through the same tmux and status-file path as any direct report.
When seeded with `-`, the home is a durable treehouse lease under the lieutenant id, so it survives with no live process and is not recycled by later `treehouse get` or pruning.
Retirement or seed rollback returns the leased home; normal restart/recovery keeps it leased.
If returning the lease fails during teardown, numberone leaves the route and home intact instead of hiding a still-held lease.
Seeding is transactional: if validation, cloning, initialization, or registry update fails, generated briefs, new homes, new project clones, and registry edits are rolled back.
`local-only` projects stay with the main Number One because they merge into the main local checkout instead of a remote-backed PR path.
The same project may appear in multiple lieutenant homes when their scopes differ, such as issue triage versus feature development.
Lieutenants are idle by default: after startup recovery reconciles only work already in their own home, an empty queue waits silently for routed tasks, and they never self-initiate surveys or audits.
Bare `n1-send.sh n1-<id>` requests to a live `kind=lieutenant` are prefixed with the from-numberone marker from `bin/n1-marker-lib.sh`, so the lieutenant returns terse answers through status lines and detailed answers through docs plus status pointers instead of replying only in its own chat.
Explicit `session:window` sends and direct human typing stay unmarked, so captain intervention in a lieutenant pane remains conversational.
After seeding a lieutenant, `n1-backlog-handoff.sh` moves already-judged in-scope queued items from the main backlog into that lieutenant home so the domain queue starts in the right place.
Idle lieutenant panes are healthy; teardown is explicit and refuses while the lieutenant home has in-flight work unless the captain has approved discard with `--force`.

Lieutenant homes stay on the same numberone version as the primary checkout.
On main numberone bootstrap, `n1-bootstrap.sh` fast-forwards each live lieutenant home recorded in `state/*.meta` to the primary default-branch commit with no origin fetch.
A tracked-files fast-forward leaves the home's gitignored `data/`, `state/`, `config/`, `projects/`, and `.no-mistakes/` directories untouched.
Dirty, diverged, unsafe, or in-flight homes are reported and left unchanged.
Only a running lieutenant home that actually advanced and changed `AGENTS.md`, `bin/`, or `.agents/skills/` is listed for a re-read nudge.
`n1-spawn.sh --lieutenant` performs the same guarded local fast-forward before launch or recovery respawn; skipped syncs warn and the lieutenant launches unchanged.

The `data/lieutenants.md` line schema and the lieutenant environment variables are documented in [configuration.md](configuration.md).

## Project modes are explicit

`data/projects.md` records each project's delivery mode and optional `+yolo` autonomy flag.
`no-mistakes` projects run the full validation pipeline, `direct-PR` projects open PRs without that pipeline, and `local-only` projects stay local until numberone performs an approved fast-forward merge.
Teardown is fail-closed for mission worktrees: dirty worktrees refuse, and committed work must be landed before the worktree is returned.
Landed work is accepted when `HEAD` is reachable from any remote-tracking branch, when a PR for the current `HEAD` is merged, or when the worktree content is already present in the freshly fetched default branch.
That content check lets a squash-merged PR whose head branch was deleted tear down cleanly without using `--force`; `local-only` work instead tears down after the approved local default-branch merge or after the branch is pushed to any remote.

## Optional X mode

X mode is opt-in presence for the shared `@myfirstmate` bot.
A user enables it by putting `FMX_PAIRING_TOKEN` in the numberone home's gitignored `.env`; `FMX_RELAY_URL` is optional and defaults to `https://myfirstmate.io`.
That token is standing authorization for numberone to answer public mentions and act autonomously on normal reversible mention requests.
Destructive, irreversible, or security-sensitive asks are escalated for trusted-channel confirmation instead of being executed from a public mention.
The relay uses owner-only routing: a mention delivered to a home is from that home's owner, while parent-thread context may still include other public accounts.
On bootstrap, that token creates two local artifacts: `state/x-watch.check.sh`, which performs one bounded relay poll through `bin/n1-x-poll.sh`, and `config/x-mode.env`, which sets `N1_CHECK_INTERVAL=30` for watcher arms in that home.
Without the token, bootstrap removes those artifacts on opt-out and otherwise stays silent, so non-X users see no behavior change.
Pending mentions are stored as `state/x-inbox/<request_id>.json`; the `fmx-respond` agent-only skill drains that inbox, uses `in_reply_to` parent-tweet context for conversational continuity, classifies each mention as an actionable request, question, or pure acknowledgment, and submits public-safe replies through `bin/n1-x-reply.sh`.
Actionable reversible requests run through numberone's normal intake, backlog, dispatch, investigation, or mission lifecycle.
Work that completes in the answering turn gets one outcome reply.
Work that spawns a longer-running task gets an acknowledgement reply first; `bin/n1-x-link.sh` records `x_request=` and `x_request_ts=` in that task's `state/<id>.meta`, and the terminal completion wake later uses `bin/n1-x-followup.sh` to post one public-safe follow-up through the relay's `connector/followup` endpoint.
The follow-up is bounded by a local 24h window, clears the link after success or expiry, and is skipped for tasks that did not originate from an X mention.
Pure acknowledgments or mentions with nothing to answer are dismissed through `bin/n1-x-dismiss.sh`, which calls the relay's `connector/dismiss` endpoint and posts no text, then the local inbox file is cleared.
Concise replies stay single unnumbered tweets; genuinely long replies are split by the client into bounded, numbered text threads on word boundaries, with `texts` carrying the ordered chunks for the relay.
For preview testing, `FMX_DRY_RUN` makes `n1-x-reply.sh` and `n1-x-dismiss.sh` skip the public post or dismiss call and record the full would-be payload under `state/x-outbox/`, including `texts` when the reply would be a thread and an `endpoint` marker when the preview is a completion follow-up or dismiss, while the rest of the poll -> compose -> would-post loop still succeeds.
The watcher, wake queue, arm wrapper, and afk daemon are unchanged; X mode is layered on top through the existing check mechanism.

## Project memory belongs to projects

Durable project-intrinsic agent knowledge lives in each project's committed `AGENTS.md`, with `CLAUDE.md` as a symlink.
Mission briefs prompt ensigns to create or update those files through the normal delivery path; `data/projects.md` stays a thin private registry.
The full ownership rule - what is project-intrinsic versus fleet-private, and how numberone keeps the two apart without writing into project clones - is owned by numberone's operating manual in [`AGENTS.md`](../AGENTS.md) (project memory ownership).

## Local clones stay fresh

Bootstrap and PR-based teardown refresh remote-backed project clones when the clone is safe to move.
Clean default-branch clones fast-forward to `origin/<default>`, and a clean detached HEAD that holds no unique commits is re-attached to the default branch before the same fast-forward path runs.
Dirty clones, non-default branches, detached HEADs with unique commits, diverged defaults, and default branches checked out in another worktree are reported as `STUCK:` with their behind count and left untouched.
Local-only projects, clones without an origin remote, and fetch failures remain benign skips.
The refresh also prunes local branches whose remote is gone and that no worktree still needs.

## Self-updates stay safe

`/updatenumberone` fast-forwards the running numberone repo and registered lieutenant homes from `origin`, then re-reads updated instructions and nudges updated lieutenants without touching project clones.
The update is fast-forward only: dirty, diverged, offline, and off-default targets are reported and left untouched.
The origin-based updater and the local lieutenant sync share the same guarded fast-forward helper; only the origin mode fetches.
The mechanics are owned by the `/updatenumberone` skill and numberone's operating manual in [`AGENTS.md`](../AGENTS.md) (self-update).

## Restart-proof

All state lives in tmux, no-mistakes run records, status event logs, local markdown under `data/`, `data/lieutenants.md`, and persistent lieutenant homes.
Kill the Number One session anytime; the next one reconciles and carries on.

## Development notes

The current watcher reliability work combines always-on bash triage with a durable queue for actionable wakes, a race-proof singleton lock, duplicate self-eviction, drain-time liveness assertion, and a self-verifying tracked-child arm wrapper.
The presence-gated sub-supervisor (`bin/n1-supervise-daemon.sh`) provides walk-away supervision via the `/afk` skill while reusing the same shared wake classifier as the always-on watcher.
