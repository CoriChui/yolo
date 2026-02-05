---
name: yolo:do
description: Execute small ad-hoc tasks with tracking
argument-hint: "[description] or [list|continue|complete|cancel] [id] [--profile]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Task
---

<objective>
Execute small ad-hoc tasks with YOLO guarantees:
- Atomic commits
- Full tracking in DO.yaml
- Multiple tasks in parallel
- Execution history

**Default profile:** budget (fast and cheap). Override with `--profile <name>`.

**Subcommands:**
- `/yolo:do [description]` — Start new task
- `/yolo:do list` — Show active and recent tasks
- `/yolo:do continue [id]` — Continue working on a task
- `/yolo:do complete [id]` — Mark task as complete
- `/yolo:do cancel [id]` — Cancel a task
</objective>

<execution_context>
@./.claude/yolo/workflows/do.md
@./.claude/yolo/templates/do.yaml
@./.claude/yolo/orchestration/agent-orchestrator.md
</execution_context>

<context>
Arguments: $ARGUMENTS

Check for existing DO.yaml:
```bash
cat .planning/do/DO.yaml 2>/dev/null | head -50
```
</context>

<process>

## Parse Subcommand

Parse $ARGUMENTS to determine action:
- Empty or description text → Start new task
- `list` → Show tasks
- `continue [id]` → Continue task
- `complete [id]` → Complete task
- `cancel [id]` → Cancel task

Parse flags:
- `--profile <name>` → Agent profile (default: budget)

---

## Flow: Start New Task

**If $ARGUMENTS is a description (not a subcommand):**

### Step 1: Initialize

```bash
mkdir -p .planning/do
```

If DO.yaml doesn't exist, create from template.

### Step 2: Get Description

Use $ARGUMENTS as description. If empty, ask:

```
AskUserQuestion(
  header: "Task",
  question: "What needs to be done?",
  options: null
)
```

### Step 3: Generate ID and Slug

```bash
# Find next number
last=$(ls -1d .planning/do/[0-9][0-9][0-9]-* 2>/dev/null | sort -r | head -1 | xargs -I{} basename {} | grep -oE '^[0-9]+')
next_num=$(printf "%03d" $((10#${last:-0} + 1)))

# Slug from description (lowercase, hyphens, max 30 chars)
```

### Step 4: Explore Codebase

Before planning, explore relevant code. Can delegate to research agent for complex tasks:
- For simple tasks: direct Glob/Grep/Read
- For complex tasks: `spawn_agent_with_profile("research", ..., profile)` (default: research-quick via budget profile)

1. Determine scope from description
2. Find relevant files (Glob, Grep)
3. Read key files
4. Understand current architecture in this area

### Step 5: Create Plan

Create `.planning/do/${next_num}-${slug}/plan.md`:

```markdown
# Do ${next_num}: ${DESCRIPTION}

**Started:** ${date}
**Status:** in_progress

## Context

[What was discovered during codebase exploration]

## Tasks

- [ ] Task 1: Description
  - Files: `path/to/file.ts`

- [ ] Task 2: Description
  - Files: `path/to/another.ts`

## Notes

[Additional notes]
```

### Step 6: User Approval

Present the plan to user for approval before executing.

### Step 7: Update DO.yaml

Add to Active section in DO.yaml.

### Step 8: Execute Tasks

For each task:
1. Explore task files
2. Make changes
3. Verify (lint, types if applicable)
4. Commit atomically with message referencing /do #ID

### Step 9: Output

```
───────────────────────────────
YOLO > /do STARTED

#${next_num}: ${DESCRIPTION}

Tasks: ${task_count}
Profile: ${profile}
Directory: .planning/do/${next_num}-${slug}/

Executing tasks...
───────────────────────────────
```

---

## Flow: List Tasks

**If $ARGUMENTS is `list`:**

Read DO.yaml and display:

```
AD-HOC TASKS (/do)
──────────────────

Active (N):
  #003  Description       in_progress  2/3 tasks
  #002  Description       blocked      1/2 tasks

Recent Completed (N):
  #001  Description       2026-02-01

Commands:
  /yolo:do continue 003
  /yolo:do complete 003
  /yolo:do "new task"
```

---

## Flow: Continue Task

**If $ARGUMENTS is `continue [id]`:**

1. Find task directory: `.planning/do/${id}-*/`
2. Read plan.md to get current state
3. Find next incomplete task
4. Execute it
5. Update plan.md and DO.yaml

---

## Flow: Complete Task

**If $ARGUMENTS is `complete [id]`:**

1. Verify all tasks in plan.md are marked `[x]`
2. Create summary.md
3. Move from Active to Completed in DO.yaml
4. Update statistics
5. Commit

---

## Flow: Cancel Task

**If $ARGUMENTS is `cancel [id]`:**

1. Confirm with user
2. Move from Active to Cancelled in DO.yaml
3. Update plan.md with cancelled status

</process>

<success_criteria>
- [ ] DO.yaml exists and is up-to-date
- [ ] Each task has directory with plan.md
- [ ] Commits are atomic with reference to /do #ID
- [ ] History preserved in DO.yaml
- [ ] Statistics updated
- [ ] User approval step before execution
- [ ] Profile flag respected (default: budget)
</success_criteria>
