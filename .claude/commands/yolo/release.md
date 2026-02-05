---
name: yolo:release
description: Create and manage releases (major feature sets)
argument-hint: "[new|start|status|end|focus|list] [args] [--profile]"
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
Manage releases — the top-level work containers.

**Key principle:** Multiple releases can run in parallel. Use `/release focus` to switch context. Commands operate on the **focused release** by default. Use `--release <id>` to override.

**Subcommands:**
- `/yolo:release new <slug>` — Create pending release + intake version
- `/yolo:release start [id]` — Start release (runs research, defines features)
- `/yolo:release status [id]` — Show release state
- `/yolo:release end [id]` — Complete release, lock intake
- `/yolo:release focus <id>` — Set focused release for commands
- `/yolo:release list` — List all releases

**Profiles:** Use `--profile <name>` to control agent quality (quality/balanced/budget/guided). Default: balanced.

**Flow:**
```
/release new mvp           ← pending + intake created, set as focused
/intake capture figma      ← gather materials for focused release
/release start             ← research, define features (uses agents)
/feature start 01-auth     ← work on features
/feature complete

/release new mobile        ← second release, now focused
/release focus mvp         ← switch back to mvp
/release end               ← complete focused release, intake locked
```
</objective>

<execution_context>
@./.claude/yolo/workflows/release-new.md
@./.claude/yolo/workflows/release-start.md
@./.claude/yolo/workflows/release-status.md
@./.claude/yolo/workflows/release-end.md
@./.claude/yolo/workflows/release-focus.md
@./.claude/yolo/orchestration/agent-orchestrator.md
</execution_context>

<context>
Arguments: $ARGUMENTS

Check current state:
```bash
cat .planning/state.yaml 2>/dev/null | grep -A5 "^focus:" && \
cat .planning/state.yaml 2>/dev/null | grep -A20 "^releases:"
```
</context>

<process>

## Parse Subcommand

Parse $ARGUMENTS:
- `new <slug>` → Create new pending release
- `start [id]` → Start pending release (research + features)
- `status [id]` → Show release state
- `end [id]` → Complete active release
- `focus <id>` → Set focused release
- `list` → List all releases
- `requirements [id]` → Show release requirements.md
- Empty → Show status

Parse flags:
- `--profile <name>` → Agent profile (quality/balanced/budget/guided)
- `--release <id>` or `-r <id>` → Override focused release

---

## Flow: New

**If $ARGUMENTS starts with `new`:**

1. Generate release ID: `{date}-{slug}` (e.g., `2026-02-04-mvp`)
2. Create release directory: `.planning/releases/{id}/`
3. Create release.yaml with PENDING status
4. Create intake directory with `{slug}-v1`
5. Add to `releases:` array in state.yaml
6. Set as focused release in `focus.release`
7. Report success with next steps

---

## Flow: Start

**If $ARGUMENTS is `start` or `start <id>`:**

1. Resolve release (from arg, or focused release)
2. Check release status is PENDING
3. Explore codebase using agent-based research (`spawn_agent_with_profile("research", ..., profile)`)
4. Read intake for context
5. Define goal and success criteria
6. Auto-create features from research
7. Create requirements.md
8. Set release status to ACTIVE
9. Report success

---

## Flow: Status

**If $ARGUMENTS is `status` or `status <id>` or empty:**

Display release state:
```
RELEASES
────────
★ 2026-02-04-mvp (active) [FOCUSED]
  Progress: ████████░░░░░░░░░░░░ 50% (2/4 features)
  Intake: mvp-v1.1 (open)

○ 2026-02-10-mobile (pending)
  Progress: not started
  Intake: mobile-v1 (open)
```

If specific ID provided, show detailed view for that release.

---

## Flow: End

**If $ARGUMENTS is `end` or `end <id>`:**

1. Resolve release (from arg, or focused release)
2. Check release status is ACTIVE (reject if pending/paused/failed/cancelled/completed with appropriate messages)
3. For each incomplete feature:
   - [Complete] Mark as done
   - [Detach] Move to standalone
   - [Archive] Keep as-is
4. Lock intake (no more captures)
5. Generate output specs (schema.md, api.md, architecture.md)
6. Set release status to COMPLETED
7. If focused release was completed, suggest `/release focus` for another
8. If there are incomplete features: present option to detach to standalone

---

## Flow: Focus

**If $ARGUMENTS starts with `focus`:**

1. Parse release ID from arguments
2. Verify release exists in `releases:` array
3. Update `focus.release` in state.yaml
4. Report new focus context

---

## Flow: List

**If $ARGUMENTS is `list`:**

Display all releases:
```
RELEASES
────────
ID                     Status    Features  Intake
2026-02-04-mvp         active    2/4       mvp-v1.1 (open)     [FOCUSED]
2026-02-10-mobile      pending   0/0       mobile-v1 (open)
2026-01-15-pilot       completed 5/5       pilot-v2 (locked)
```

</process>

<success_criteria>
- [ ] Release state managed correctly
- [ ] Intake tied to release
- [ ] Features defined on start
- [ ] State transitions enforced
- [ ] Multiple parallel releases supported
- [ ] Focus switching works
</success_criteria>
