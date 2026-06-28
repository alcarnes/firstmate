---
name: lieutenant-provisioning
description: Agent-only reference for persistent lieutenant setup and retirement. Use when creating, seeding, validating, recovering, handing backlog to, or retiring a lieutenant home, or when editing data/lieutenants.md. Covers home leases, transactional seeding, project clone restrictions, idle charter, handoff helper, and teardown safety.
user-invocable: false
---

# lieutenant-provisioning

Use this reference before creating, seeding, validating, handing backlog to, recovering, or retiring a persistent lieutenant, and before editing `data/lieutenants.md`.

Keep the always-inline routing rules in `AGENTS.md` authoritative: route by natural-language `scope:`, local-only projects stay with the main numberone, and lieutenants are idle by default.

## Routing table

`data/lieutenants.md` has one line per persistent domain supervisor:

```markdown
- <id> - <charter summary> (home: <absolute-home-path>; scope: <natural-language responsibility>; projects: <project-a>, <project-b>; added <date>)
```

The `scope:` field is used during intake.
The `projects:` field is a non-exclusive clone list, not ownership.

## Charter and seed

Scaffold a lieutenant charter with:

```sh
bin/n1-brief.sh <id> --lieutenant <project>...
```

The scaffold writes a charter brief instead of a task brief.
Set `N1_LIEUTENANT_CHARTER='<charter>'` to fill the charter text and `N1_LIEUTENANT_SCOPE='<scope>'` when the routing scope differs.
If you scaffold without `N1_LIEUTENANT_CHARTER`, replace the `{TASK}` placeholder before seeding.
Keep the charter focused on the persistent responsibility, available project clones, escalation back to the main numberone status file, and the requests-from-main-numberone contract.
The scaffold's definition of done encodes the idle-by-default contract: on startup the lieutenant reconciles only its own in-flight work and then waits for routed tasks, never self-initiating a survey or audit.
Preserve that wording when filling the charter, including the marker rule that marked supervisor requests return through status or a doc pointer while unmarked captain messages stay conversational.

Provision the persistent home and registry entry after the charter is filled:

```sh
bin/n1-home-seed.sh <id> <home|-> <project>...
```

`-` durably leases a fresh numberone worktree via `treehouse get --lease` under the lieutenant id.
The lease survives with no live process and is never recycled by later `treehouse get` or `prune`.
The slot stays reserved across restarts until the lease is released.
Release happens only on explicit retirement or seed rollback, never on routine restart or recovery.

`bin/n1-home-seed.sh` copies the charter into the lieutenant home as `data/charter.md`.
`bin/n1-spawn.sh --lieutenant` launches it through the same launch-template path.
Before launch, `n1-spawn.sh --lieutenant` locally fast-forwards the home to the primary numberone checkout's current default-branch commit when it is safe; dirty, diverged, or in-flight homes launch unchanged with a warning.
`bin/n1-home-seed.sh` refuses to copy a missing or placeholder charter.

Direct seed without a preexisting brief requires `N1_LIEUTENANT_CHARTER`.
Run `bin/n1-home-seed.sh validate` when checking registry integrity; it refuses duplicate ids, duplicate homes, and nested or overlapping homes.

Seeding is transactional.
If validation, cloning, no-mistakes initialization, or registry update fails, generated briefs, new homes, new project clones, and registry edits are rolled back.

Lieutenant project lists may include `no-mistakes` and `direct-PR` projects only.
`local-only` projects stay with the main numberone.
For `no-mistakes` projects, seeding initializes only projects newly cloned into a lieutenant home and refuses to mutate a preexisting clone that is not already initialized.

## Backlog handoff

When a lieutenant is created for a domain, existing main-backlog items that fall under its scope should become its work instead of staying stranded in the main backlog.
Scope-matching is numberone's judgment against the lieutenant's natural-language scope, not a keyword rule.
Read `data/backlog.md`, pick queued items that fit the new scope, and move them with:

```sh
bin/n1-backlog-handoff.sh <lieutenant-id> <item-key>...
```

After seeding, run this handoff for the new lieutenant's in-scope queued items.
The helper resolves the lieutenant home from `data/lieutenants.md` and mechanically moves each named item from the main `data/backlog.md` into the lieutenant home's `data/backlog.md`.
It preserves the line and its section, so the item is neither duplicated nor lost.
It refuses `## In flight` entries because active task ownership also lives in tmux and `state/`.
It is idempotent; an item already in the lieutenant backlog is skipped.
It refuses any destination that is not a genuine seeded numberone home with safe operational directories and a matching `.n1-lieutenant-home` marker, so a move can never land in a project.
Do not hand off `local-only` items.

## Recovery

For `kind=lieutenant` meta with no window, treat the lieutenant as a dead persistent direct report and respawn it with:

```sh
bin/n1-spawn.sh <id> --lieutenant
```

Use the recorded `home=` in meta.
If meta is missing but `data/lieutenants.md` still registers the lieutenant, respawn from the registry entry and its persistent on-disk home.
Respawn uses the same guarded pre-launch sync, so recovered lieutenants converge to the primary numberone version without fetching from origin whenever their home can be cleanly fast-forwarded.

Do not reconstruct a lieutenant's whole tree from the main home.
The main numberone reconciles only direct reports.
Each lieutenant is a numberone in its own home, so it runs recovery on startup and reconciles its own ensigns.
A lieutenant's recovery reconciles only work that is already its own and then idles.
It never initiates a survey or audit during recovery.

## Retirement and teardown

A lieutenant is persistent by default.
An empty queue is healthy and does not trigger teardown.
Run `bin/n1-teardown.sh <id>` for `kind=lieutenant` only when the captain or main numberone explicitly decides to retire that persistent supervisor.

The safety check is the lieutenant's own home.
Teardown refuses while its `state/*.meta` contains in-flight work.
When safe, teardown kills the direct tmux window, removes the `data/lieutenants.md` route, clears the main home metadata, and removes the retired lieutenant home.
Removing a leased home releases its durable treehouse lease via `treehouse return`, so the pool slot is freed for reuse rather than left leased forever.
A plain-clone home with no pool slot is simply removed.
If `treehouse return` fails for a leased home, teardown stops with state intact rather than raw-removing the directory and hiding a held lease.

With `--force`, teardown is the explicit discard path.
It kills child windows, discards child work and state inside the lieutenant home, removes the route, releases the lease, and removes the retired lieutenant home.
Never use `--force` unless the captain explicitly said to discard the work.
