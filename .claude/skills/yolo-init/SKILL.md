---
name: yolo-init
description: Use when setting up YOLO in a project for the first time, or repairing the setup. Scaffolds workspace/config.yaml and the features/ + intake/ dirs, and installs the CLAUDE.md routing block. Triggers on "set up YOLO here", "init yolo", "yolo init".
---

# yolo-init

Make a repo YOLO-ready. Idempotent — safe to re-run (repair mode).

## Procedure
1. Create `workspace/`, `workspace/features/`, `workspace/intake/`, `workspace/decisions/` if missing (each tracked; add a `.gitkeep` where empty).
2. If `workspace/config.yaml` is missing, copy `.claude/yolo/templates/config.yaml` to it; set `project.name` to the repo directory name and `project.base_branch` (use `main`, else `master`). If it exists, repair only: fill missing keys, never overwrite a user-set value.
3. Install the routing block: ensure the project `CLAUDE.md` contains the content of `.claude/yolo/templates/claude-routing-block.md`. If the `<!-- YOLO:routing-block start -->`/`end` markers already exist, replace the block between them; otherwise append it. (Idempotent.)
4. Commit (`chore(yolo): initialize`).

## Constraints
- Never git-ignore `workspace/` — it is the durable spine and must survive branches/worktrees.
- Repair mode preserves existing config values; it only fills gaps.
