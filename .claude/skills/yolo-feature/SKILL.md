---
name: yolo-feature
description: Use when the user wants to build, add, or implement a feature. Captures intent, drafts a brief, confirms, then composes research → plan → execute → verify → finish. In a YOLO-initialized repo this takes precedence over generic brainstorming for feature intent.
---

# yolo-feature

The conversational entry point. You turn "I want X" into a landed, verified change.
Cheap steps run freely; billed steps are gated.

## 1. Capture intent (cheap — no confirmation needed)
- Ask a light 2-question check (skip with `--skip-qa` or `ux.mode: auto`): what the user can DO after this, and how they'd know it works.
- Derive a `slug`, `goal`, and `success_criteria`. Write `workspace/features/<slug>/brief.md` from `.claude/yolo/templates/brief.md`. Commit it (`brief: <slug>`). The brief now existing = status "planned" (`.claude/yolo/conventions.md`).

## 2. Confirm before billed work (the gate)
Show the drafted brief and the intended path. STOP and get approval before spawning any billed agent or writing code (skip only in `ux.mode: auto`).

## 3. Branch (and worktree only if needed)
`git switch -c feature/<slug>`. Create a worktree (`../.<repo>-worktrees/<slug>`) only if work will run in parallel or you need walk-away isolation (§4.7); otherwise a plain branch.

## 4. Compose the atoms
- **yolo-research** — invoke when the change is non-trivial or the codebase is unfamiliar; skip for tiny obvious changes (`--no-research`).
- **yolo-plan** — produce `plan.md`; present for approval.
- **execute** — for each task in `plan.md`, work test-first (use superpowers:test-driven-development), and commit that task with `--trailer "YOLO-Task: <id>"`. Use subagents for isolation when tasks are independent.
- **yolo-verify** — check `success_criteria`; on pass it writes the `YOLO-Verified: true` trailer.
- **yolo-finish** — land per the finishing policy + risk classifier.

## Rules
- Honor `workspace/config.yaml` `ux.mode` (interactive/guided/auto) for how much you ask.
- Store no status — every "where are we" is derived from git via yolo-status.
- Precedence: in a YOLO repo, feature intent routes here; generic brainstorming yields.
- The atoms are defined once in their own skills — invoke them, don't reimplement them here.
