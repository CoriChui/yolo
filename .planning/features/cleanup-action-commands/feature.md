---
goal: Remove action slash commands (init, start, release, intake, feature, decide) now that autonomous hooks and git-as-truth make them redundant; keep only informational commands (status, debug, help).
branch: feature/cleanup-action-commands
worktree: /Users/konstantintsoy/Desktop/web/yolo
created: 2026-04-16
test_commands: ["bash scripts/yolo-cli/test-lib.sh", "bash scripts/yolo-cli/test-hook-pre-write.sh"]
lint_commands: ["bash -n scripts/yolo-cli/lib.sh"]
---

## Criteria
- [ ] Six action slash commands are removed from `.claude/commands/yolo/`: init, start, release, intake, feature, decide.
- [ ] Three informational commands remain: status, debug, help.
- [ ] `/yolo:help` output reflects the new command surface without broken references.

## Context

With the gate-hardening and git-as-truth features shipped, YOLO now derives
intent from actions (edits, bash writes) rather than explicit slash commands.
Feature lifecycle is driven by branch state + commit trailers. Action commands
like `/yolo:start`, `/yolo:release`, and `/yolo:intake` are vestigial — they
duplicate what the autonomous hooks already do.

Keep only:
- `/yolo:status` — reconciles and reports current state (observability)
- `/yolo:debug` — starts a debug session (specific workflow, not covered by hooks)
- `/yolo:help` — lists remaining commands

Everything else is deleted so the surface area matches the autonomous design.

## Plan

1. [ ] Delete the six action command files — `init.md`, `start.md`, `release.md`, `intake.md`, `feature.md`, `decide.md` — from `.claude/commands/yolo/` so the slash-command surface shrinks to only informational entries that cannot be inferred from state
  - files: .claude/commands/yolo/init.md, .claude/commands/yolo/start.md, .claude/commands/yolo/release.md, .claude/commands/yolo/intake.md, .claude/commands/yolo/feature.md, .claude/commands/yolo/decide.md
  - test: none (file-deletion verified by test 3)

2. [ ] Rewrite `.claude/commands/yolo/help.md` to reflect the reduced command surface, drop the removed command sections, and add a short explanation that actions are now driven by intent-detection and hooks rather than explicit slash commands
  - files: .claude/commands/yolo/help.md
  - test: bash scripts/yolo-cli/test-lib.sh

3. [ ] Add a decision record at `.planning/decisions/2026-04-16-remove-action-commands.md` documenting why the surface was reduced, what the autonomous replacement is, and what to do when users ask for the removed commands
  - files: .planning/decisions/2026-04-16-remove-action-commands.md
  - test: bash scripts/yolo-cli/test-hook-pre-write.sh

## Verification
(Written by check step)
