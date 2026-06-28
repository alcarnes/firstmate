---
name: stuck-ensign-recovery
description: Agent-only playbook for stuck numberone direct reports. Use after a stale wake, looping pane, repeated confusion, an answered-by-brief question, an unresponsive ensign, or a failed steer. Escalates from peek, to one-line steer, to harness-specific interrupt, to relaunch with progress, to failed status.
user-invocable: false
---

# stuck-ensign-recovery

Use this playbook when a direct report is stale, looping, repeatedly confused, asking a question its brief already answers, unresponsive, or when a steer failed to land.

Load `harness-adapters` before sending an interrupt, exit command, resume command, or harness-specific skill invocation.
The target window's harness is recorded as `harness=` in `state/<id>.meta`.

Escalate in order:

1. Peek the pane.
2. If the ensign is waiting on a question its brief already answers, answer in one line via `bin/n1-send.sh`.
3. If the ensign is confused or looping, interrupt with the adapter's interrupt key, then redirect with one corrective line.
   For example, for a single-Escape adapter: `bin/n1-send.sh <window> --key Escape`.
4. If the ensign is genuinely wedged after redirection, exit the agent with the adapter's exit command and relaunch with the same brief plus a `progress so far` note appended to it.
   Genuine wedging means looping, unresponsive, repeating the same obstacle, or truly dead.
   A low context reading is not wedging; modern harnesses auto-compact and keep going.
   The worktree and commits persist, so relaunch is cheap.
5. If a second relaunch fails too, write `failed` to the backlog and tell the captain with evidence.
