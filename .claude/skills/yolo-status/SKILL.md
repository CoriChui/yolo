---
name: yolo-status
description: Use when the user asks where things stand, what's in progress, or "where was I". Computes a derived view of every feature's status from git and the briefs — nothing is read from a stored status field.
---

# yolo-status

Report the state of all features by DERIVING it from git (`.claude/yolo/conventions.md`). There is no stored status field — do not look for one.

## Procedure
1. Read `workspace/config.yaml` `project.base_branch` (detect `main`, else `master`).
2. For each `workspace/features/*/brief.md`, take `<slug>` from the folder and derive status:
   - **done** — `feature/<slug>` is merged into base (`git branch --merged <base>` lists it), OR the branch tip carries `YOLO-Verified: true` with a committed `verification.md`.
   - **in-progress** — `feature/<slug>` exists and is not merged. Completed tasks:
     `git log <base>..feature/<slug> --format='%(trailers:key=YOLO-Task,valueonly)' | sed '/^$/d'` (count vs the task total in `plan.md`).
   - **planned** — brief exists, no branch.
3. Group rows by the brief's `milestone:` value when set.
4. Print a compact table: slug · status · tasks(done/total, for in-progress) · milestone. Add a one-line resume hint from the most recent in-progress branch's last commit subject.

## Constraints
- Read-only. Compute, never store. This view cannot be stale because it is recomputed each call.
