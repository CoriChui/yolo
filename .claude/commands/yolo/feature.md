---
name: yolo:feature
description: Use when starting, resuming, or managing a feature inside the active release — runs the full pipeline (research → plan → execute → review → hook gate → verify → complete), amends plans, adds features, or reports feature status. Requires an active release.
argument-hint: "[start|plan|verify|complete|status|add] [args] [--prompt] [--amend] [--force]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Task
  - ToolSearch
  - WebSearch
  - WebFetch
  - TeamCreate
  - TaskCreate
  - TaskUpdate
  - TaskList
  - TaskGet
  - SendMessage
  - TeamDelete
---

<objective>
Manage features — release-scoped work units.

**Subcommands:**
- `/yolo:feature start <id> [--force]` — Full pipeline: research → plan → execute → review → hook gate → verify → complete (`--force` bypasses missing dependency checks)
- `/yolo:feature start <id> --prompt "<text>"` — Start with custom instructions
- `/yolo:feature plan [--amend] [--force] [--prompt "<text>"]` — Create or amend execution plan (`--force` overrides researching recency check)
- `/yolo:feature verify [--force]` — Check success criteria (auto-completes on pass; `--force` bypasses hook_gate_failed guard). Calling on in_progress skips hook gate
- `/yolo:feature complete` — Mark feature complete, merge worktree (requires passed verification)
- `/yolo:feature status [id]` — Show feature progress
- `/yolo:feature add <name> [--prompt "<goal>"]` — Add a new feature to the active release

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
- **else** → Error: "Unknown subcommand '{arg}'. Run `/yolo:help` for usage."

Parse flags:
- `--amend` → Amend existing plan (for `plan` subcommand)
- `--prompt "<text>"` → Feature goal (required for `add`), custom instructions for `start`, `plan`, and research + planning stages
- `--force` → For `verify`: bypass `hook_gate_failed` guard. For `start`: bypass missing dependency checks. For `plan`: override researching recency check.

Read `.claude/yolo/workflows/feature.md` and follow the matching subcommand section.

</process>
