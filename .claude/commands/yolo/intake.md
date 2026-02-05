---
name: yolo:intake
description: Capture and manage auxiliary intake materials from 26+ source types
argument-hint: "[capture|add|diff|status|list] [args] [--release]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
---

<objective>
Manage auxiliary intake materials from external sources.

**Key principle:** Intake operates on the **focused release** by default. Use `--release <id>` to override.

**Subcommands:**
- `/yolo:intake capture [source]` — Capture from 26+ sources (MCP, WebFetch, CLI, local files)
- `/yolo:intake add <path>` — Add local files/projects as .md digests
- `/yolo:intake diff <v1> <v2>` — Compare two versions
- `/yolo:intake status` — Show current intake state
- `/yolo:intake list` — List all intake versions

**Flow:**
```
/release new mvp             ← creates release + intake mvp-v1
/intake capture figma        ← capture from Figma MCP
/intake capture gdocs        ← capture Google Docs/Sheets via WebFetch
/intake capture db           ← capture live DB schema via CLI
/intake add ./specs/api.md   ← add file as .md digest
/intake diff mvp-v1 mvp-v1.1 ← compare versions
/release start               ← start working
/release end                 ← intake locked

/release new mobile          ← creates intake mobile-v1
/intake capture figma --release 2026-02-10-mobile  ← capture to specific release
```

**State machine:**
- No release → intake capture BLOCKED
- Release pending → intake OPEN
- Release active → intake OPEN
- Release ended → intake CLOSED
</objective>

<execution_context>
@./.claude/yolo/workflows/intake-capture.md
@./.claude/yolo/workflows/intake-status.md
@./.claude/yolo/workflows/intake-list.md
@./.claude/yolo/workflows/intake-diff.md
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
- `capture [source]` → Capture from source (requires release)
- `add <path>` → Add local files/projects as .md digests (requires release)
- `diff <v1> <v2>` → Compare two intake versions
- `status` → Show current intake
- `list` → List all versions
- Empty → Show status

Parse flags:
- `--release <id>` or `-r <id>` → Override focused release

---

## Flow: Capture

**If $ARGUMENTS starts with `capture`:**

1. **RESOLVE RELEASE** — from `--release` flag or focused release
2. **CHECK RELEASE EXISTS** — must have pending or active release
3. **CHECK INTAKE NOT LOCKED** — release must not be completed
4. Determine source from catalog (26+ types across MCP, WebFetch, CLI, local, interactive)
5. Check if source already captured
6. Capture content as .md digests to: `.planning/releases/{id}/intake/{slug}-v{N}/`
7. Update manifest and state

---

## Flow: Add

**If $ARGUMENTS starts with `add`:**

1. **RESOLVE RELEASE** — from `--release` flag or focused release
2. **CHECK RELEASE EXISTS** — must have pending or active release
3. **CHECK INTAKE NOT LOCKED**
4. Parse file path from arguments
5. Digest source into .md files (never copy raw source files)
6. Update manifest and state

---

## Flow: Diff

**If $ARGUMENTS starts with `diff`:**

Parse: `diff <version1> <version2>`

1. Resolve release context
2. Locate both intake versions in release directory
3. Compare files between versions:
   - New files added
   - Files removed
   - Files modified (content diff)
4. Display summary of changes

---

## Flow: Status

**If $ARGUMENTS is `status` or empty:**

Resolve release (from `--release` flag or focused release).
Display current intake version, sources, file counts.
Show release association.

```
INTAKE STATUS (2026-02-04-mvp)
─────────────────────────────
Version: mvp-v1.1
Created: 2026-02-10
Locked: no

Sources:
  figma/: 3 .md files
  gdocs/: 1 .md file
  notes/: 2 .md files
```

---

## Flow: List

**If $ARGUMENTS is `list`:**

Resolve release. List all intake versions for that release:

```
mvp-v1      2026-02-03  major  figma+notion
mvp-v1.1    2026-02-10  patch  +notes
```

</process>

<success_criteria>
- [ ] Release exists before capture/add
- [ ] Sources accumulate in version
- [ ] Intake locked on release end
- [ ] Manual add creates patch version
- [ ] Diff shows meaningful comparison
- [ ] --release flag overrides focused release
</success_criteria>
