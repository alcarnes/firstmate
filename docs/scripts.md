# The bin/ toolbelt

The Number One drives these; interactive entrypoints work by hand too, while `*-lib.sh` files are sourced helpers.
Each file also starts with a short header comment.

| Script                   | Description                                                                                                         |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `n1-bootstrap.sh`        | Detect required toolchain and version problems, optional capability facts, primary-checkout `TANGLE:` problems, and actionable clone refresh outcomes; refresh project clones best-effort; locally sync live lieutenant homes; set up opt-in X mode; install tools only after consent |
| `n1-fleet-sync.sh`       | Fetch clones, fast-forward safe default-branch states, self-heal clean detached ancestor drift, report unsafe drift as `STUCK:`, and safely prune branches whose remote is gone |
| `n1-update.sh`           | Self-update the running numberone repo and registered lieutenant homes with fast-forward-only pulls from origin     |
| `n1-backlog-handoff.sh`  | Move already-judged in-scope queued backlog items from the main home into a seeded lieutenant home                 |
| `n1-brief.sh`            | Scaffold a mission brief with a worktree-isolation assertion, a report-only survey brief with `--survey`, or a lieutenant charter with `--lieutenant` |
| `n1-ensure-agents-md.sh` | Ensure project `AGENTS.md` is the real memory file and `CLAUDE.md` symlinks to it                                   |
| `n1-guard.sh`            | Warn when the primary checkout is tangled, when queued wakes are pending, or when a stale or missing watcher needs a prominent banner |
| `n1-home-seed.sh`        | Lease/provision a lieutenant home transactionally, clone projects, initialize gates, and maintain `data/lieutenants.md` |
| `n1-spawn.sh`            | Spawn one task, several `id=repo` pairs, or a persistent lieutenant with `--lieutenant`; mission/survey spawns require an isolated treehouse worktree; lieutenant spawns locally sync the home before launch |
| `n1-project-mode.sh`     | Resolve a project's delivery mode and `+yolo` flag from `data/projects.md`                                          |
| `n1-merge-local.sh`      | Fast-forward a `local-only` project's local default branch after approval                                           |
| `n1-review-diff.sh`      | Review a ensign branch against the authoritative base, with optional `--stat` output                              |
| `n1-marker-lib.sh`       | Shared from-numberone request marker and detector sourced by `n1-send.sh`, `n1-brief.sh`, and tests                 |
| `n1-watch-arm.sh`        | Verified per-home watcher re-arm; reports `started`, `healthy`, or `FAILED`; `--restart` relaunches only this home's watcher |
| `n1-watch.sh`            | Singleton-safe always-on watcher; absorbs benign wakes in bash, queues and exits only for actionable wakes, and reverts to daemon-owned one-shot behavior while `state/.afk` exists |
| `n1-supervise-daemon.sh` | Presence-gated sub-supervisor for walk-away (`/afk`) supervision: wraps `n1-watch.sh`, uses the shared wake classifier, self-handles routine wakes in bash, and escalates only captain-relevant events as one verified, batched, single-line digest prefixed with a sentinel marker |
| `n1-crew-state.sh`       | Print one stable current-state line for a crew by reconciling its matching no-mistakes run-step, even when the pane has closed, with pane and status-log fallback |
| `n1-tangle-lib.sh`       | Shared default-branch resolution and primary-checkout tangle classification sourced by bootstrap and guard         |
| `n1-ff-lib.sh`           | Shared guarded fast-forward helper for `/updatenumberone` origin pulls and no-fetch local lieutenant syncs         |
| `n1-tasks-axi-lib.sh`    | Shared `tasks-axi` compatibility probe sourced by bootstrap and teardown                                            |
| `n1-wake-drain.sh`       | Atomically drain queued watcher wakes before handling supervision work, then run the watcher-liveness guard         |
| `n1-wake-lib.sh`         | Shared durable wake queue and portable lock helpers sourced by the watcher, drain, arm, guard, and daemon          |
| `n1-classify-lib.sh`     | Shared captain-relevant wake classifier sourced by the watcher and sub-supervisor daemon                           |
| `n1-send.sh`             | Send one verified literal line (or `--key Escape`) to a direct-report window; exits non-zero on confirmed swallowed Enter; bare `kind=lieutenant` targets are marked as from-numberone; slash commands and codex `$...` skill invocations get popup-settle before Enter; text sends pause `N1_SEND_SETTLE` seconds after success |
| `n1-tmux-lib.sh`         | Shared tmux pane primitives for busy detection, dim-ghost-aware and border-aware composer detection, and verified submit retry |
| `n1-peek.sh`             | Print a bounded tail of a ensign pane                                                                             |
| `n1-pr-check.sh`         | Record `pr=` and a verified `pr_head=` when available for a PR-ready task, then arm the watcher's merge poll        |
| `n1-promote.sh`          | Promote a survey task in place so it becomes a protected mission task                                                   |
| `n1-teardown.sh`         | Return a clean, landed mission worktree or retire/release a lieutenant home; requires survey reports, checks child work, and prints the backlog reminder |
| `n1-harness.sh`          | Detect the running harness; resolve the effective ensign harness                                                  |
| `n1-lock.sh`             | Per-home numberone session lock                                                                                     |
| `n1-x-lib.sh`            | Shared X-mode `.env`, alternate env-file, relay, dry-run config, reply-thread splitting, and task-to-X-request meta-link helpers |
| `n1-x-poll.sh`           | Do one bounded X relay poll; without `FMX_PAIRING_TOKEN` it is silent, with a pending mention it stashes the full inbox JSON, including `in_reply_to`, and prints `x-mention <request_id>` |
| `n1-x-reply.sh`          | Post or dry-run preview a composed public-safe X answer or `--followup`, auto-splitting long text into `{request_id,text,texts}` threads; reads text from an argument, stdin, or `--text-file` |
| `n1-x-dismiss.sh`        | Dismiss or dry-run preview a skipped X mention without replying by sending `{request_id}` to the relay's `connector/dismiss` endpoint |
| `n1-x-link.sh`           | Link a spawned task to its originating X mention by recording `x_request=` and `x_request_ts=` in `state/<id>.meta` |
| `n1-x-followup.sh`       | Detect, post, and clear the single completion follow-up for an X-linked task, enforcing the local 24h window and retrying only when the relay post fails |
