---
name: yolo:debug
description: Use when you hit a bug, test failure, or unexpected behavior and need root-cause analysis — not a quick patch. Starts a persistent debug session with reproducer, evidence chain, failing test, and fix.
argument-hint: "new <symptom> | resume [id] | list | end <id>"
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
Systematic debugging using the scientific method with persistent state.
Debug sessions survive context resets via `.planning/debug-sessions/`.

Subcommands:
  /yolo:debug new <symptom>   — Start a new debug session
  /yolo:debug resume [id]     — Resume an existing session
  /yolo:debug list             — Show all sessions
  /yolo:debug end <id>         — Close a session (resolved or abandoned)
</objective>

<process>

## Parse Subcommand

Parse $ARGUMENTS:
- `new <symptom>` → Start new session
- `resume [id]` → Resume session
- `list` → Show all sessions
- `end <id>` → Close session
- Empty or bare symptom → Start new session

## Start New Session

1. **Slug:** derive from symptom (`echo "$symptom" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\{2,\}/-/g' | cut -c1-30`)
2. **Dir:** `mkdir -p .planning/debug-sessions/${slug}`
3. **Gather symptoms:** ask for expected behavior, actual behavior, error messages, reproduction steps
4. **Create session file** at `.planning/debug-sessions/${slug}/session.md`:

```markdown
# Debug: ${slug}

**Status:** investigating
**Started:** ${date}

## Symptom
${symptom}

## Current Focus
**Hypothesis:** [first hypothesis]
**Test:** [how to test]
**Next:** [first action]

## Evidence
| Checked | Found | Implication |
|---------|-------|-------------|

## Eliminated
| Hypothesis | Evidence Against |
|------------|------------------|

## Resolution
**Root Cause:** —
**Fix:** —
**Verification:** —
```

5. **Dispatch debug agent** via Task tool with the symptom and working directory.
6. **Apply fix** if agent identifies root cause and user approves.

## Resume Session

1. Read `.planning/debug-sessions/${id}/session.md`
2. Check Current Focus → know where we left off
3. Check Eliminated → know what NOT to retry
4. Check Evidence → know what we've learned
5. Continue from Next action, dispatching debug agent if needed

## List Sessions

```
DEBUG SESSIONS
──────────────
Active:
  ${slug}  ${status}  "${current_hypothesis}"

Resolved:
  ${slug}  ${date}  "${root_cause}"
```

## End Session

1. Verify root cause is documented (if resolved)
2. Update status in session.md
3. Confirm with user

</process>
