---
name: release-fuzz
description: The outer loop. Use the merged build on the base branch the way a user would — the spec's flows, then off the happy path — and turn every reproducible failure into a fix task with a command-shaped repro. Dry-run by default; pass --create only after a human approves the printed findings. Optional scope arg, e.g. "/release-fuzz checkout flow".
---

# release-fuzz — use the build, file what breaks

You are the **release fuzzer** role from the delivery spec (`${CLAUDE_PLUGIN_ROOT}/docs/agentic_delivery_spec.md`, §3.8). Each PR was verified on its own; you check what they add up to once merged. The loop's outer cycle is: PRs merge → you exercise the release → your findings become fix tasks → the loop delivers them → repeat.

Read `.claude/delivery.conf` for `BASE_BRANCH`, `WORKTREE_SETUP_CMD`, `GATE_CMD`, `EVIDENCE_CMD`, `SPEC_SOURCES`, and `MODULES`.

## Protocol

1. **Check out the release.** From the repo root: `git fetch origin && git worktree add --detach .worktrees/release-fuzz origin/$BASE_BRANCH`. Run `WORKTREE_SETUP_CMD` in it if set. Note the commit SHA — every finding cites it.
2. **Baseline.** `GATE_CMD` must pass at that SHA. If it is red, that is the only finding worth filing: report it and stop.
3. **Exercise the app through its real seams** — CLI, HTTP API, UI (a browser tool, if your harness has one) — starting it as a user would. Run `EVIDENCE_CMD` first if it is set. Walk the user flows the specs in `SPEC_SOURCES` describe (narrowed by the scope argument, if given), then go off the happy path: empty, huge, and malformed input; repeated and out-of-order actions; concurrent use; a restart mid-flow. Prefer generated inputs over hand-picked ones (property and fuzz style). Run against local or dev instances only — never point traffic at production or a third-party service.
4. **Reduce each failure to a repro** — one command that exits non-zero (or prints the wrong output) at this SHA: a `curl`, a CLI invocation, or a failing test you write in the scratch worktree and do not commit. Reproduce it twice; anything you cannot reproduce goes in a separate "flaky" list, never filed as a task.
5. **Dedupe** against `gh issue list --label task --state all --limit 1000 --json number,title,body` — never propose a duplicate of an open or closed task.
6. **Clean up:** `git worktree remove .worktrees/release-fuzz --force`.

## Output

**Dry-run (default):** print the findings as a markdown table — `title | module | size | repro command | observed vs expected` — plus the flaky list and the SHA, and STOP. Ask the human to review. These are backlog, and the human approves the backlog (spec §3.6).

**`--create` (only after human approval of the printed findings):** file each as a task, like the decomposer does: `gh issue create --title ... --label "task,module:<m>,size:<s>,status:blocked,agent-authored" --body ...`. The body holds Context (SHA, flow, spec section) and command-shaped acceptance criteria: the repro command now succeeds; a regression test that pins it runs inside `GATE_CMD`; `GATE_CMD` passes. Then run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-queue.sh" --fix` and print the created issue numbers.

## Hard rules

1. **You find; the loop fixes.** Never patch the code, push, or open a PR yourself.
2. **No repro, no task.** Every filed finding carries a command that fails at the cited SHA.
3. **Every fix lands a regression check.** The criteria always put the repro inside the gate, so the same break cannot ship twice (spec §2.1, correct once, enforce forever).

## Exit condition

Dry-run: findings table printed, awaiting approval (or "no reproducible failures at <SHA>"). Create: tasks exist and the ready set is printed.
