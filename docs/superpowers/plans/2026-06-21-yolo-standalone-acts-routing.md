# YOLO Standalone Acts + Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the five standalone YOLO skills (`yolo-status`, `yolo-roadmap`, `yolo-intake`, `yolo-decide`, `yolo-init`) and install the **CLAUDE.md routing block** that makes feature intent trigger `yolo-feature` conversationally — completing the user-facing surface of reasoning-first YOLO.

**Architecture:** Same skill model as Plan 2 — each is `.claude/skills/<name>/SKILL.md` with frontmatter + procedure, citing the Plan 1 contracts. `yolo-status` is the derived-state view (the payoff of git-as-truth: a report that can't be stale). `yolo-init` installs the routing block from a template, so the conversational entry is reproducible in any repo. Verification is structural acceptance checks plus a real behavioral trigger test (this plan is where triggering becomes testable).

**Tech Stack:** Markdown + YAML frontmatter, git, shell. Depends on Plan 1 (`conventions.md`, `templates/`, `workspace/`) and Plan 2 (the five methodology skills referenced by routing).

**Prerequisite:** Plans 1 and 2 are committed. Routing references `yolo-feature` (Plan 2), so Plan 2 must exist first.

**Spec reference:** `docs/superpowers/specs/2026-06-21-yolo-reasoning-first-redesign.md` §4.2 (derived status → `yolo-status`), §4.3 (intake shelf → `yolo-intake`), §4.4 (the standalone-acts rows), §4.5 (conversational entry + precedence → routing block, **resolves open question Q4**), §4.8 (decomposition → `yolo-roadmap`).

**Cross-skill contract (verbatim):** brief `workspace/features/<slug>/brief.md`; intake shelf `workspace/intake/<source>/`; decisions `workspace/decisions/<slug>.md`; config `workspace/config.yaml`; branch `feature/<slug>`; trailers `YOLO-Task:`/`YOLO-Verified: true`; routing markers `<!-- YOLO:routing-block start -->` / `end`.

Reusable frontmatter check (define in your shell before the tasks):

```bash
check_skill () {
  python3 - "$1" <<'PY'
import sys,yaml
name=sys.argv[1]; t=open(f".claude/skills/{name}/SKILL.md").read()
assert t.startswith("---"), "no frontmatter"
fm=yaml.safe_load(t.split("---",2)[1])
assert fm.get("name")==name, f"name mismatch {fm.get('name')}"
assert isinstance(fm.get("description"),str) and len(fm["description"])>20, "weak description"
print(f"FRONTMATTER OK: {name}")
PY
}
```

---

## File Structure

- `.claude/skills/yolo-status/SKILL.md` — derived-state report from git + briefs.
- `.claude/skills/yolo-roadmap/SKILL.md` — decompose a big goal → N briefs (shared `milestone`).
- `.claude/skills/yolo-intake/SKILL.md` — JIT fetch or persist external material to the shelf.
- `.claude/skills/yolo-decide/SKILL.md` — multi-perspective decision → `workspace/decisions/`.
- `.claude/skills/yolo-init/SKILL.md` — scaffold config/dirs + install the routing block.
- `.claude/yolo/templates/claude-routing-block.md` — the routing block `yolo-init` installs (Q4).
- `CLAUDE.md` (repo root) — created/updated in Task 6 to host the routing block in THIS repo.
- `docs/superpowers/plans/acceptance/standalone-acts-consistency.md` — consistency check.

---

### Task 1: `yolo-status` skill (the derived-state view)

**Files:**
- Create: `.claude/skills/yolo-status/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.claude/skills/yolo-status/SKILL.md` with exactly this content:

```markdown
---
name: yolo-status
description: Use when the user asks where things stand, what's in progress, or "where was I". Computes a derived view of every feature's status from git and the briefs — nothing is read from a stored status field.
---

# yolo-status

Report the state of all features by DERIVING it from git (`.claude/yolo/conventions.md`). There is no stored status field — do not look for one.

## Procedure
1. Read `workspace/config.yaml` `project.base_branch` (detect `main`, else `master`).
2. For each `workspace/features/*/brief.md`, take `<slug>` from the folder and derive status:
   - **done** — `feature/<slug>` is merged into base (`git branch --merged <base>` lists it), OR the branch tip carries `YOLO-Verified: true` with a committed `verification.md`.
   - **in-progress** — `feature/<slug>` exists and is not merged. Completed tasks:
     `git log <base>..feature/<slug> --format='%(trailers:key=YOLO-Task,valueonly)' | sed '/^$/d'` (count vs the task total in `plan.md`).
   - **planned** — brief exists, no branch.
3. Group rows by the brief's `milestone:` value when set.
4. Print a compact table: slug · status · tasks(done/total, for in-progress) · milestone. Add a one-line resume hint from the most recent in-progress branch's last commit subject.

## Constraints
- Read-only. Compute, never store. This view cannot be stale because it is recomputed each call.
```

- [ ] **Step 2: Verify**

```bash
check_skill yolo-status
grep -q 'git branch --merged' .claude/skills/yolo-status/SKILL.md && echo "DERIVES-DONE"
grep -q 'YOLO-Task' .claude/skills/yolo-status/SKILL.md && echo "DERIVES-TASKS"
grep -qi 'never store\|cannot be stale\|read-only' .claude/skills/yolo-status/SKILL.md && echo "NO-STORE-OK"
```
Expected: `FRONTMATTER OK: yolo-status`, `DERIVES-DONE`, `DERIVES-TASKS`, `NO-STORE-OK`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/yolo-status/SKILL.md
git commit -m "feat(yolo): yolo-status skill — derived state view from git"
```

---

### Task 2: `yolo-roadmap` skill

**Files:**
- Create: `.claude/skills/yolo-roadmap/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.claude/skills/yolo-roadmap/SKILL.md` with exactly this content:

```markdown
---
name: yolo-roadmap
description: Use when the user has a large or fuzzy goal that should be decomposed into several features. Produces N feature briefs (optionally sharing a milestone label) — a one-time act that returns briefs, not a container. Triggers on "break this epic into features", "plan a milestone", "decompose this".
---

# yolo-roadmap

Turn one big goal into several atomic feature briefs. There is no "release" container — just briefs, optionally tagged with a shared `milestone`.

## Procedure
1. Clarify the big goal and its boundary (what's out of scope). Optionally invoke yolo-research for codebase context.
2. Decompose into independent features, each shippable on its own. Note any cross-feature `depends_on` (honored by the model; there is no DAG machine).
3. For each feature, draft `workspace/features/<slug>/brief.md` from `.claude/yolo/templates/brief.md` — set `goal`, `success_criteria`, and a shared `milestone:` value if they ship as a set.
4. Present the proposed feature list for approval BEFORE creating the briefs (a planning gate; no billed code work happens here).
5. On approval, write and commit the briefs. Each is later picked up by yolo-feature.

## Constraints
- You only create briefs (status "planned"). You do not branch, plan, or execute — that is yolo-feature, per feature.
- No container, no lifecycle, no status field. Grouping is the `milestone:` label only.
```

- [ ] **Step 2: Verify**

```bash
check_skill yolo-roadmap
grep -q 'workspace/features/<slug>/brief.md' .claude/skills/yolo-roadmap/SKILL.md && echo "WRITES-BRIEFS"
grep -qi 'no container\|no.*lifecycle' .claude/skills/yolo-roadmap/SKILL.md && echo "NO-CONTAINER-OK"
grep -q 'milestone' .claude/skills/yolo-roadmap/SKILL.md && echo "MILESTONE-OK"
grep -q 'yolo-feature' .claude/skills/yolo-roadmap/SKILL.md && echo "HANDS-OFF-OK"
```
Expected: `FRONTMATTER OK: yolo-roadmap`, `WRITES-BRIEFS`, `NO-CONTAINER-OK`, `MILESTONE-OK`, `HANDS-OFF-OK`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/yolo-roadmap/SKILL.md
git commit -m "feat(yolo): yolo-roadmap skill — decompose goal into briefs"
```

---

### Task 3: `yolo-intake` skill

**Files:**
- Create: `.claude/skills/yolo-intake/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.claude/skills/yolo-intake/SKILL.md` with exactly this content:

```markdown
---
name: yolo-intake
description: Use when the user references external material (Figma, a Google Doc, a DB schema, an API spec, a URL) to bring into context. Fetches just-in-time for cheap/live sources; persists a digest only for expensive, rate-limited, or offline sources. Triggers on "pull in this Figma/doc/schema", "use this spec".
---

# yolo-intake

Bring external material into reach. The shelf is project-level (`workspace/intake/`), owned by no release.

## Decide: just-in-time vs persist
- **Just-in-time** (default for cheap/live sources — a URL, an MCP-reachable doc): fetch now, use it, cite it. Do NOT persist a digest.
- **Persist** (only for expensive / rate-limited / offline sources — a large Figma, a DB you don't want to hammer, a PDF): write a `.md` digest under `workspace/intake/<source>/` so it is reusable across features and commits.

## Procedure
1. Identify the source type and reach it (MCP tool, WebFetch, a CLI, or a local file).
2. If persisting: write the digested `.md` under `workspace/intake/<source>/` and commit. If JIT: keep it in working context only.
3. A feature brief references persisted intake via its `intake_refs` list.

## Constraints
- Never persist secrets verbatim — strip `.env`/credentials before writing a digest.
- The shelf is shared across all features. Never nest intake under a feature or a "release".
```

- [ ] **Step 2: Verify**

```bash
check_skill yolo-intake
grep -q 'workspace/intake/<source>/' .claude/skills/yolo-intake/SKILL.md && echo "SHELF-PATH-OK"
grep -qi 'just-in-time' .claude/skills/yolo-intake/SKILL.md && grep -qi 'persist' .claude/skills/yolo-intake/SKILL.md && echo "JIT-VS-PERSIST-OK"
grep -qi 'intake_refs' .claude/skills/yolo-intake/SKILL.md && echo "REFS-OK"
grep -qi 'strip.*secret\|secret.*strip\|\.env' .claude/skills/yolo-intake/SKILL.md && echo "SECRET-GUARD-OK"
```
Expected: `FRONTMATTER OK: yolo-intake`, `SHELF-PATH-OK`, `JIT-VS-PERSIST-OK`, `REFS-OK`, `SECRET-GUARD-OK`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/yolo-intake/SKILL.md
git commit -m "feat(yolo): yolo-intake skill — project-level shelf + JIT fetch"
```

---

### Task 4: `yolo-decide` skill

**Files:**
- Create: `.claude/skills/yolo-decide/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.claude/skills/yolo-decide/SKILL.md` with exactly this content:

```markdown
---
name: yolo-decide
description: Use when facing a design or architecture decision that benefits from multiple perspectives before committing. Produces a decision record under workspace/decisions/. Triggers on "help me decide X vs Y", "which approach", "should we use A or B".
---

# yolo-decide

Reach a defensible decision via multi-perspective analysis, and record it.

## Procedure
1. State the decision and the options crisply.
2. Argue each option from several lenses — at minimum correctness/risk, simplicity/maintainability, and pragmatism/cost. Surface the strongest case FOR and AGAINST each.
3. Recommend one option, with explicit rationale, the alternatives considered, dissents (minority concerns worth recording), and revisit triggers (conditions that should reopen this).
4. Write `workspace/decisions/<slug>.md` with: decision, rationale, approach, alternatives_considered, dissents, revisit_triggers, confidence. Confirm before overwriting an existing slug.
5. Commit (`chore: decision <slug>`).

## Constraints
- Read-only with respect to code; the only file you write is the decision record.
- No status field; decisions are standalone records.
```

- [ ] **Step 2: Verify**

```bash
check_skill yolo-decide
grep -q 'workspace/decisions/<slug>.md' .claude/skills/yolo-decide/SKILL.md && echo "DECISION-PATH-OK"
grep -qi 'revisit triggers\|dissents' .claude/skills/yolo-decide/SKILL.md && echo "RECORD-FIELDS-OK"
grep -qi 'confirm before overwriting' .claude/skills/yolo-decide/SKILL.md && echo "OVERWRITE-GATE-OK"
```
Expected: `FRONTMATTER OK: yolo-decide`, `DECISION-PATH-OK`, `RECORD-FIELDS-OK`, `OVERWRITE-GATE-OK`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/yolo-decide/SKILL.md
git commit -m "feat(yolo): yolo-decide skill — multi-perspective decision record"
```

---

### Task 5: `yolo-init` skill + the routing-block template (resolves Q4)

**Files:**
- Create: `.claude/yolo/templates/claude-routing-block.md`
- Create: `.claude/skills/yolo-init/SKILL.md`

- [ ] **Step 1: Write the routing-block template**

Create `.claude/yolo/templates/claude-routing-block.md` with exactly this content:

```markdown
<!-- YOLO:routing-block start -->
## YOLO workflow (this is a YOLO-initialized repo)

This project uses YOLO (reasoning-first). Feature state lives in **git, not in tracked
status files** — see `.claude/yolo/conventions.md`.

**Routing — when the user expresses intent to build, add, or implement a feature**, use the
`yolo-feature` skill: capture intent → draft a brief → CONFIRM → compose
research/plan/execute/verify/finish. In this repo this takes **precedence over generic
brainstorming** for feature intent.

**Cheap vs billed:** intent capture and brief drafting run freely; **STOP for confirmation
before** spawning a billed agent or writing code (unless `workspace/config.yaml`
`ux.mode: auto`).

**Other intents:** "where do things stand / where was I" → `yolo-status`; "break this epic
into features / plan a milestone" → `yolo-roadmap`; "pull in this Figma/doc/schema" →
`yolo-intake`; "help me decide X vs Y" → `yolo-decide`; "set up YOLO here" → `yolo-init`.
<!-- YOLO:routing-block end -->
```

- [ ] **Step 2: Write the `yolo-init` skill**

Create `.claude/skills/yolo-init/SKILL.md` with exactly this content:

```markdown
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
```

- [ ] **Step 3: Verify**

```bash
check_skill yolo-init
grep -q 'YOLO:routing-block start' .claude/yolo/templates/claude-routing-block.md && echo "MARKERS-OK"
grep -q 'yolo-feature' .claude/yolo/templates/claude-routing-block.md && echo "ROUTES-FEATURE"
grep -qi 'precedence over generic' .claude/yolo/templates/claude-routing-block.md && echo "PRECEDENCE-OK"
grep -qi 'stop for confirmation before' .claude/yolo/templates/claude-routing-block.md && echo "GATE-OK"
grep -q 'claude-routing-block.md' .claude/skills/yolo-init/SKILL.md && echo "INIT-INSTALLS-BLOCK"
grep -qi 'repair' .claude/skills/yolo-init/SKILL.md && echo "REPAIR-OK"
```
Expected: `FRONTMATTER OK: yolo-init`, `MARKERS-OK`, `ROUTES-FEATURE`, `PRECEDENCE-OK`, `GATE-OK`, `INIT-INSTALLS-BLOCK`, `REPAIR-OK`.

- [ ] **Step 4: Commit**

```bash
git add .claude/yolo/templates/claude-routing-block.md .claude/skills/yolo-init/SKILL.md
git commit -m "feat(yolo): yolo-init skill + CLAUDE.md routing block template"
```

---

### Task 6: Install the routing block into THIS repo + behavioral trigger check

This makes YOLO self-hosting here so the conversational trigger is testable (the manual check deferred from Plan 2).

**Files:**
- Create: `CLAUDE.md` (repo root)

- [ ] **Step 1: Install the routing block**

Run (appends the template block to a new or existing root `CLAUDE.md`, idempotently):
```bash
if [ -f CLAUDE.md ] && grep -q 'YOLO:routing-block start' CLAUDE.md; then
  echo "already installed"
else
  { [ -f CLAUDE.md ] && echo; cat .claude/yolo/templates/claude-routing-block.md; } >> CLAUDE.md
fi
```

- [ ] **Step 2: Verify the block is present and well-formed**

```bash
grep -q 'YOLO:routing-block start' CLAUDE.md && grep -q 'YOLO:routing-block end' CLAUDE.md && echo "BLOCK-INSTALLED"
grep -q 'yolo-feature' CLAUDE.md && echo "ROUTES-FEATURE"
# idempotency: exactly one start marker
test "$(grep -c 'YOLO:routing-block start' CLAUDE.md)" = "1" && echo "SINGLE-BLOCK"
```
Expected: `BLOCK-INSTALLED`, `ROUTES-FEATURE`, `SINGLE-BLOCK`.

- [ ] **Step 3: Behavioral trigger check (manual — record the result)**

In a fresh Claude Code session in this repo, type a plain feature request, e.g.:
> "I want users to be able to export their data as CSV"

Confirm: (a) `yolo-feature` activates and announces itself, (b) it drafts a brief at `workspace/features/<slug>/brief.md`, (c) it **stops for confirmation before** writing code, and (d) it did not get hijacked by generic brainstorming. Write PASS/FAIL + a one-line note into the commit message in Step 4. If FAIL (e.g., brainstorming won), strengthen the routing block's precedence wording and re-run.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "chore(yolo): install routing block in repo CLAUDE.md [trigger check: <PASS/FAIL + note>]"
```

---

### Task 7: Consistency check across all standalone-act skills

**Files:**
- Create: `docs/superpowers/plans/acceptance/standalone-acts-consistency.md`

- [ ] **Step 1: Write the check**

Create `docs/superpowers/plans/acceptance/standalone-acts-consistency.md` with exactly this content:

````markdown
# Acceptance: Standalone acts + routing consistency

Run from repo root.

```sh
set -e
fail=0
for s in yolo-status yolo-roadmap yolo-intake yolo-decide yolo-init; do
  f=".claude/skills/$s/SKILL.md"
  test -f "$f" || { echo "MISSING $f"; fail=1; continue; }
  head -1 "$f" | grep -qx -- '---' || { echo "NO-FRONTMATTER $s"; fail=1; }
  grep -q "name: $s" "$f" || { echo "NAME-MISMATCH $s"; fail=1; }
done
grep -q 'git branch --merged' .claude/skills/yolo-status/SKILL.md || { echo "status not deriving"; fail=1; }
grep -q 'workspace/features/<slug>/brief.md' .claude/skills/yolo-roadmap/SKILL.md || { echo "roadmap path"; fail=1; }
grep -q 'workspace/intake/<source>/' .claude/skills/yolo-intake/SKILL.md || { echo "intake shelf path"; fail=1; }
grep -q 'workspace/decisions/<slug>.md' .claude/skills/yolo-decide/SKILL.md || { echo "decide path"; fail=1; }
test -f .claude/yolo/templates/claude-routing-block.md || { echo "routing template missing"; fail=1; }
grep -q 'yolo-feature' .claude/yolo/templates/claude-routing-block.md || { echo "routing not pointing at feature"; fail=1; }
grep -q 'YOLO:routing-block start' CLAUDE.md || { echo "routing block not installed in repo"; fail=1; }
test "$fail" = 0 && echo "ALL-CONSISTENT" || { echo "INCONSISTENT"; exit 1; }
```

Expected final line: `ALL-CONSISTENT`.
````

- [ ] **Step 2: Run it**

```bash
sed -n '/^```sh$/,/^```$/p' docs/superpowers/plans/acceptance/standalone-acts-consistency.md | sed '1d;$d' | bash
```
Expected: `ALL-CONSISTENT`.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/acceptance/standalone-acts-consistency.md
git commit -m "test(yolo): standalone acts + routing consistency check"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** §4.2 derived status → Task 1. §4.8 decomposition → Task 2. §4.3 intake shelf + JIT → Task 3. `yolo-decide` (intact) → Task 4. `yolo-init` + §4.5 routing block (Q4) → Tasks 5–6. Conversational trigger becomes testable → Task 6 Step 3.

**Placeholder scan:** Every SKILL.md and the routing-block template are given in full; the only `<...>` are intentional path placeholders (`<slug>`, `<source>`) that are part of the contract, plus the Task 6 commit's `<PASS/FAIL + note>` which the implementer fills from the actual trigger result.

**String consistency:** Paths (`workspace/features/<slug>/brief.md`, `workspace/intake/<source>/`, `workspace/decisions/<slug>.md`), routing markers, and `yolo-feature` reference are identical across Tasks 1–7. Task 7 re-asserts each. The routing block names every skill this plan creates plus the Plan 2 `yolo-feature`.

**Out of scope (Plan 4):** deletion of `.claude/yolo/spec.md`, `agents/`, `workflows/`, and `.claude/commands/yolo/`.
