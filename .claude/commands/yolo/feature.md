---
name: yolo:feature
description: Manage features — release-scoped or standalone
argument-hint: "[new|start|plan|execute|verify|complete|attach|detach|list|status] [args] [--release|--standalone|--profile]"
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
Manage features — units of work, release-scoped or standalone.

**Subcommands:**
- `/yolo:feature new <slug>` — Create new standalone feature
- `/yolo:feature start <id>` — Start working on feature
- `/yolo:feature plan` — Create execution plan
- `/yolo:feature execute` — Execute planned tasks
- `/yolo:feature verify` — Check success criteria
- `/yolo:feature complete` — Mark feature complete
- `/yolo:feature attach <feature> <release>` — Attach standalone to release
- `/yolo:feature detach <feature-id> <release>` — Detach from release to standalone
- `/yolo:feature list` — List all features
- `/yolo:feature status` — Current feature details

**Flags:**
- `--release <id>` or `-r` — Specify release (overrides focused release)
- `--standalone` — Filter standalone features only (for list)
- `--profile <name>` — Agent profile (quality/balanced/budget/guided)

**Flow (release-scoped):**
```
/feature start 01-auth     ← start feature in focused release
/feature plan              ← create detailed plan (uses agents)
/feature execute           ← implement the plan (uses agents)
/feature verify            ← check criteria met (uses agents)
/feature complete          ← mark done, move to next
```

**Flow (standalone):**
```
/feature new dark-mode     ← create standalone feature
/feature start dark-mode   ← start working
/feature attach dark-mode 2026-02-04-mvp  ← attach to release
```
</objective>

<execution_context>
@./.claude/yolo/workflows/feature-start.md
@./.claude/yolo/workflows/feature-plan.md
@./.claude/yolo/workflows/feature-execute.md
@./.claude/yolo/workflows/feature-verify.md
@./.claude/yolo/workflows/feature-complete.md
@./.claude/yolo/workflows/feature-attach.md
@./.claude/yolo/workflows/feature-detach.md
@./.claude/yolo/orchestration/agent-orchestrator.md
</execution_context>

<context>
Arguments: $ARGUMENTS

Check current state:
```bash
cat .planning/state.yaml 2>/dev/null | grep -A10 "^feature:" && \
cat .planning/state.yaml 2>/dev/null | grep -A5 "^focus:" && \
cat .planning/state.yaml 2>/dev/null | grep -A10 "^standalone_features:"
```
</context>

<process>

## Parse Subcommand

Parse $ARGUMENTS:
- `new <slug>` → Create standalone feature
- `start <id>` → Start feature by ID
- `plan` → Plan current feature
- `execute` → Execute current feature
- `verify` → Verify current feature
- `complete` → Complete current feature
- `attach <feature> <release>` → Attach standalone to release
- `detach <feature-id> <release>` → Detach from release
- `list` → List all features
- `status` → Current feature details
- Empty → Show status or list

Parse flags:
- `--release <id>` or `-r <id>` → Override focused release
- `--standalone` → Filter standalone only
- `--profile <name>` → Agent profile

---

## Flow: New

**If $ARGUMENTS starts with `new`:**

1. Parse slug from arguments
2. Create `.planning/features/{slug}/` directory
3. Create feature.yaml with `release: null` (standalone)
4. Set status: pending
5. Add to `standalone_features:` in state.yaml
6. Report success

---

## Flow: Start

**If $ARGUMENTS starts with `start`:**

1. Parse feature ID and optional `--release <id>` flag
2. Resolve feature location:
   - Release feature: `.planning/releases/{release}/features/{id}/`
   - Standalone feature: `.planning/features/{id}/`
3. Check feature not already completed
4. Set feature as current in `focus.feature` and `focus.feature_release`
5. Set feature.status = researching
6. Show feature goal and context
7. Suggest `/yolo:feature plan`

---

## Flow: Plan

**If $ARGUMENTS is `plan`:**

1. Check current feature exists
2. Explore codebase using agent-based research (`spawn_agent_with_profile("research", ..., profile)`)
3. Create detailed execution plan using plan agent (`spawn_agent_with_profile("plan", ..., profile)`)
4. Present plan to user for approval before proceeding
5. Save plan to feature directory
6. Set feature.status = planning

---

## Flow: Execute

**If $ARGUMENTS is `execute`:**

1. Check plan exists
2. For each task, delegate to execute agent (`spawn_agent_with_profile("execute", ..., profile)`)
3. Track progress in state.yaml
4. Commit changes atomically

---

## Flow: Verify

**If $ARGUMENTS is `verify`:**

1. Check feature criteria
2. Delegate verification to verify agent (`spawn_agent_with_profile("verify", ..., profile)`)
3. Report verification results
4. If failed, trigger `on-verification-failed` for auto-fix

---

## Flow: Complete

**If $ARGUMENTS is `complete`:**

1. Verify all criteria met
2. Mark feature as completed
3. Update release progress (if release-scoped)
4. Update `standalone_features:` (if standalone)
5. Suggest next feature

---

## Flow: Attach

**If $ARGUMENTS starts with `attach`:**

Parse: `attach <feature-slug> <release-id>`

1. Verify standalone feature exists at `.planning/features/{slug}/`
2. Verify release exists in `releases:` array
3. Assign sequential ID within release (e.g., `04-{slug}`)
4. Move `.planning/features/{slug}/` → `.planning/releases/{release}/features/{id}-{slug}/`
5. Update feature.yaml: `release` → release ID
6. Update release.yaml: add to features list
7. Remove from `standalone_features:` in state.yaml
8. Commit changes

---

## Flow: Detach

**If $ARGUMENTS starts with `detach`:**

Parse: `detach <feature-id> <release-id>`

1. Verify release feature exists at `.planning/releases/{release}/features/{id}/`
2. Extract slug from feature ID (e.g., `02-auth` → `auth`)
3. Move `.planning/releases/{release}/features/{id}/` → `.planning/features/{slug}/`
4. Update feature.yaml: `release` → null
5. Update release.yaml: remove from features list
6. Add to `standalone_features:` in state.yaml
7. Commit changes

---

## Flow: List

**If $ARGUMENTS is `list`:**

Parse flags: `--release <id>`, `--standalone`

Display all features with status:
```
FEATURES
────────
Release: 2026-02-04-mvp [FOCUSED]
  ✅ 01-foundation  (completed)
  ✅ 02-auth        (completed)
  🔄 03-billing     (in progress)
  ⏳ 04-repairs     (pending)

Standalone:
  ⏳ dark-mode      (pending)
  ⏳ export-csv     (pending)
```

If `--release <id>` specified, show only that release's features.
If `--standalone` specified, show only standalone features.

---

## Flow: Status

**If $ARGUMENTS is `status`:**

Display current feature details:
```
FEATURE: 03-billing (in progress)
───────────────────────────────
Release: 2026-02-04-mvp
Goal: Implement billing system

Tasks: ████░░░░░░ 33% (2/6)
  ✅ Set up billing service
  ✅ Create transaction model
  🔄 Implement payment acceptance (current)
  ⏳ Daily charges
  ⏳ Auto-penalties
  ⏳ Display balance
```

---

## Flow: Resume

**If $ARGUMENTS is `resume`:**

1. Check for feature with status `in_progress`, `researching`, `planning`, or `verifying`
2. Load feature context from feature.yaml
3. Determine last completed step
4. Resume from next step

> Note: Workflow file not yet created. See feature-resume.md TODO in index.yaml.

</process>

<success_criteria>
- [ ] Feature workflow followed
- [ ] Progress tracked
- [ ] Commits atomic
- [ ] Criteria verified
- [ ] Standalone features supported
- [ ] Attach/detach between release and standalone works
- [ ] Agent delegation used for plan/execute/verify
</success_criteria>
