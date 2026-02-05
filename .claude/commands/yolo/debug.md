---
name: yolo:debug
description: Systematic debugging with persistent state
argument-hint: "[issue] or [list|continue|resolve|abandon] [id] [--profile]"
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
Systematic debugging using the scientific method with persistent state across context resets.
Can use agents for research, hypothesis ranking, and fix application.

**Key features:**
- Persistent session.yaml survives `/clear`
- Eliminated hypotheses prevent re-investigation
- Evidence section builds the case
- Multiple sessions in parallel
- Agent-assisted investigation via `--profile`

**Subcommands:**
- `/yolo:debug [issue]` — Start new session or resume
- `/yolo:debug list` — Show active and resolved sessions
- `/yolo:debug continue [id]` — Continue investigating
- `/yolo:debug resolve [id]` — Mark as resolved
- `/yolo:debug abandon [id]` — Abandon session

**Profiles:** Use `--profile <name>` to control agent quality. Default: balanced.
- research-quick (budget) for initial exploration
- decide-conversation (quality/balanced) for hypothesis ranking
- execute-fix for applying fixes
</objective>

<execution_context>
@./.claude/yolo/workflows/debug.md
@./.claude/yolo/templates/debug.yaml
@./.claude/yolo/templates/debug-session.yaml
@./.claude/yolo/orchestration/agent-orchestrator.md
</execution_context>

<context>
Arguments: $ARGUMENTS

Check for active sessions:
```bash
ls -d .planning/debug/*/session.yaml 2>/dev/null | grep -v resolved | head -5
```
</context>

<process>

## Parse Subcommand

Parse $ARGUMENTS:
- Empty → Show active sessions or prompt for issue
- Issue description → Start new session
- `list` → Show all sessions
- `continue [id]` → Continue session
- `resolve [id]` → Resolve session
- `abandon [id]` → Abandon session

Parse flags:
- `--profile <name>` → Agent profile (quality/balanced/budget/guided)

---

## Flow: Start New Session

### Step 1: Initialize

```bash
mkdir -p .planning/debug
```

If DEBUG.yaml doesn't exist, create from template.

### Step 2: Check Active Sessions

If active sessions exist and no issue provided:
- List sessions with status
- User picks one to continue OR describes new issue

### Step 3: Get Issue Description

Use $ARGUMENTS or ask:

```
AskUserQuestion(
  header: "Issue",
  question: "What's the problem?",
  options: null
)
```

### Step 4: Generate Slug

```bash
slug=$(echo "$ISSUE" | tr '[:upper:]' '[:lower:]' | \
  sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-30)
DEBUG_DIR=".planning/debug/${slug}"
mkdir -p "$DEBUG_DIR"
```

### Step 5: Gather Symptoms

Ask for each:

1. **Expected behavior** — What should happen?
2. **Actual behavior** — What happens instead?
3. **Error messages** — Any errors?
4. **Timeline** — When did this start?
5. **Reproduction** — How to trigger it?

### Step 6: Create Session File

Create `${DEBUG_DIR}/session.yaml`:

Create from template at `.claude/yolo/templates/debug-session.yaml` (proper YAML format).

```markdown
# Debug: ${slug}

## Status

**Current:** investigating
**Started:** ${date}
**Updated:** ${date}

## Trigger

> ${issue_description}

## Current Focus

**Hypothesis:** [First hypothesis based on symptoms]
**Test:** [How to test it]
**Expecting:** [What result means]
**Next:** [First action]

## Symptoms

- **Expected:** ${expected}
- **Actual:** ${actual}
- **Errors:** ${errors}
- **Reproduction:** ${reproduction}
- **Timeline:** ${timeline}

## Eliminated

| Hypothesis | Evidence Against | When |
|------------|------------------|------|

## Evidence

| Checked | Found | Implication | When |
|---------|-------|-------------|------|

## Resolution

**Root Cause:** —
**Fix:** —
**Verification:** —
**Files Changed:** —
```

### Step 7: Update DEBUG.yaml

Add to Active section.

### Step 8: Begin Investigation

Scientific method loop with optional agent delegation:

1. **Form hypothesis** based on symptoms/evidence
2. **Design test** to prove/disprove
3. **Execute test** (read code, run commands, check logs)
   - Can delegate to `research-quick` agent for initial exploration of unfamiliar code areas
   - Can use `decide-conversation` agent for hypothesis ranking when multiple viable hypotheses exist
4. **Analyze result:**
   - Disproved → Add to Eliminated, new hypothesis
   - Evidence found → Add to Evidence
   - Root cause confirmed → Proceed to fix

### Step 9: On Root Cause Found

```
───────────────────────────────
ROOT CAUSE FOUND

Issue: ${slug}

Root Cause: ${root_cause}

Evidence:
- ${evidence_1}
- ${evidence_2}

Files Involved:
- ${file}: ${issue}

Options:
  [1] Fix now
  [2] Create /do task
  [3] Manual fix
───────────────────────────────
```

### Step 10: Apply Fix (if chosen)

1. Can delegate to `execute-fix` agent for applying the fix
2. Commit with reference to debug session
3. Verify fix works
4. Resolve session

---

## Flow: List Sessions

**If $ARGUMENTS is `list`:**

```
DEBUG SESSIONS
──────────────

Active (N):
  auth-token-expired    investigating   "Redis TTL"
  api-timeout           gathering       —

Resolved (N):
  login-crash           2026-02-02      "Null object"

Abandoned (N):
  memory-leak            2026-01-28      "Cannot reproduce"

Commands:
  /yolo:debug continue auth-token-expired
  /yolo:debug "new issue"
```

---

## Flow: Continue Session

**If $ARGUMENTS is `continue [id]`:**

1. Find session: `.planning/debug/${id}/session.yaml`
2. Read Current Focus → know where we left off
3. Read Eliminated → know what NOT to retry
4. Read Evidence → know what we've learned
5. Continue from Next action

---

## Flow: Resolve Session

**If $ARGUMENTS is `resolve [id]`:**

1. Verify root cause is documented
2. Verify fix is applied and verified
3. Move to `.planning/debug/resolved/`
4. Update DEBUG.yaml
5. Commit

---

## Flow: Abandon Session

**If $ARGUMENTS is `abandon [id]`:**

1. Confirm with user
2. Add reason to session.yaml
3. Move to Abandoned in DEBUG.yaml

</process>

<section_rules>
**Session file sections:**

- **Status**: OVERWRITE on status change
- **Trigger**: IMMUTABLE after creation
- **Current Focus**: OVERWRITE on each update (always reflects NOW)
- **Symptoms**: IMMUTABLE after gathering
- **Eliminated**: APPEND only (prevents re-investigating)
- **Evidence**: APPEND only
- **Resolution**: OVERWRITE as understanding evolves
</section_rules>

<success_criteria>
- [ ] DEBUG.yaml exists and tracks all sessions
- [ ] Session file created with symptoms
- [ ] Eliminated prevents re-investigation
- [ ] Root cause confirmed before fixing
- [ ] Fix verified before resolving
- [ ] Agent delegation available for research, hypothesis ranking, and fixes
- [ ] Profile flag respected
</success_criteria>
