---
name: yolo:feature
description: Manage features within releases
argument-hint: "[start|plan|verify|complete|status|add] [args] [--prompt] [--amend]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Task
  - TeamCreate
  - TaskCreate
  - TaskUpdate
  - TaskList
  - TaskGet
  - SendMessage
  - ToolSearch
  - WebSearch
  - WebFetch
---

<objective>
Manage features — release-scoped work units.

**Subcommands:**
- `/yolo:feature start <id>` — Full pipeline: research → plan → execute → verify-fix → verify → complete
- `/yolo:feature start <id> --prompt "<text>"` — Start with custom instructions
- `/yolo:feature plan [--amend]` — Create or amend execution plan
- `/yolo:feature verify` — Check success criteria
- `/yolo:feature complete` — Mark feature complete, merge worktree
- `/yolo:feature status [id]` — Show feature progress
- `/yolo:feature add <name> --prompt "<goal>"` — Add a new feature to the active release

**Flow:**
```
/feature add bugfix --prompt "Fix auth redirect loop"  ← add new feature to active release
/feature start 01-auth     ← full pipeline end-to-end
/feature plan              ← re-create plan (override)
/feature verify            ← re-run verification (override)
/feature complete          ← mark done (override)
```
</objective>

<execution_context>
Read `.claude/yolo/workflows/feature.md` for the workflow. Read `.planning/state.yaml` first.
</execution_context>

<context>
Arguments: $ARGUMENTS
</context>

<process>

## Parse Subcommand

- `add <name>` → Add new feature to active release
- `start <id>` → Full pipeline
- `plan` → Plan current feature (or `plan --amend` to amend)
- `verify` → Verify current feature
- `complete` → Complete current feature
- `status [id]` → Show feature progress (default if empty)

Parse flags:
- `--amend` → Amend existing plan (for `plan` subcommand)
- `--prompt "<text>"` → Feature goal (required for `add`), custom instructions for research + planning

Read `.claude/yolo/workflows/feature.md` and follow the matching subcommand section.

</process>
