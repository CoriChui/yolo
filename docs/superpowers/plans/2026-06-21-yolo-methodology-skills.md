# YOLO Methodology Skills Implementation Plan

> **Status: COMPLETED 2026-06-21 — historical record, not current instructions.** The live contract is `.claude/yolo/conventions.md` and the `yolo-*` skills.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the five reasoning-first skills that carry YOLO's methodology — `yolo-research`, `yolo-plan`, `yolo-verify`, `yolo-finish` (with the risk classifier), and the `yolo-feature` orchestrator — as Claude Code project skills that cite the Plan 1 contracts and drive work through git, not a state machine.

**Architecture:** Each skill is a `.claude/skills/<name>/SKILL.md` file: YAML frontmatter (`name`, `description`) that makes it auto-discoverable and intent-triggerable, plus a body of procedure. The four **atoms** (research/plan/verify/finish) are single-purpose and independently invokable; the **orchestrator** (`yolo-feature`) composes them. Skills never store status — they read/write the brief, `plan.md`, `verification.md`, and git per `.claude/yolo/conventions.md`. There is no code/test stack; tasks are verified by **structural acceptance checks** (frontmatter validity, exact-string consistency with the Plan 1 contracts) plus a documented manual behavioral check.

**Tech Stack:** Markdown + YAML frontmatter, git, shell. Depends entirely on Plan 1 contracts: `.claude/yolo/conventions.md`, `.claude/yolo/templates/{config,brief}.{yaml,md}`, `workspace/`.

**Prerequisite:** Plan 1 (Foundation) is merged/committed. Build order is **research → plan → verify → finish → feature** (orchestrator last, since it composes the others).

**Spec reference:** `docs/superpowers/specs/2026-06-21-yolo-reasoning-first-redesign.md` §4.4 (skill table + composition), §4.5 (conversational entry), §4.6 + §4.6.1 (finishing + risk classifier).

**Cross-skill contract (exact strings — every task below must use these verbatim):**
- Brief: `workspace/features/<slug>/brief.md`; plan: `…/plan.md`; verification: `…/verification.md`.
- Branch `feature/<slug>`; trailers `YOLO-Task: <task-id>` and `YOLO-Verified: true`.
- Config read from `workspace/config.yaml` (`agents.*`, `finish.*`, `risk.*`, `ux.mode`).

---

## File Structure

- `.claude/skills/yolo-research/SKILL.md` — read-only codebase + intake exploration → context note.
- `.claude/skills/yolo-plan/SKILL.md` — goal/brief → committed `plan.md` of testable tasks.
- `.claude/skills/yolo-verify/SKILL.md` — check `success_criteria` → `verification.md` + `YOLO-Verified` trailer.
- `.claude/skills/yolo-finish/SKILL.md` — finishing policy + risk classifier → PR/local landing.
- `.claude/skills/yolo-feature/SKILL.md` — orchestrator: intent → brief → confirm → compose atoms → land.

Each skill is one focused file. No existing files are modified; the old `commands/yolo/` and `workflows/` stay until Plan 4.

A reusable frontmatter check used by every task:

```bash
# usage: check_skill <name>
check_skill () {
  python3 - "$1" <<'PY'
import sys,yaml
name=sys.argv[1]
p=f".claude/skills/{name}/SKILL.md"
t=open(p).read()
assert t.startswith("---"), "no frontmatter"
fm=yaml.safe_load(t.split("---",2)[1])
assert fm.get("name")==name, f"name mismatch: {fm.get('name')} != {name}"
assert isinstance(fm.get("description"),str) and len(fm["description"])>20, "weak description"
print(f"FRONTMATTER OK: {name} — {fm['description'][:60]}...")
PY
}
```

---

### Task 1: `yolo-research` skill

**Files:**
- Create: `.claude/skills/yolo-research/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.claude/skills/yolo-research/SKILL.md` with exactly this content:

```markdown
---
name: yolo-research
description: Use before planning a YOLO change, to understand the codebase and any cited intake before a plan is written. Read-only exploration that produces context for yolo-plan. Triggers on "understand how X works", "explore the code before we change it", or as the research step of yolo-feature.
---

# yolo-research

Read-only exploration. You gather the context a plan needs; you change nothing.

## Inputs
- A brief (`workspace/features/<slug>/brief.md`) — read `goal`, `success_criteria`, `intake_refs`.
  Or, when invoked standalone, a plain question.

## Procedure
1. Identify the relevant surface: `Glob`/`Grep` for the entities, modules, and routes named in the goal.
2. Read the key files. Capture concrete `file:line` references — never vague summaries.
3. If the brief lists `intake_refs`, read those digests under `workspace/intake/<source>/`. If a needed source is live and cheap (a URL, an MCP-reachable doc), fetch it just-in-time instead of expecting a stored digest.
4. Note: existing patterns/conventions to follow, integration points, risks, and any open questions that would block planning.

## Output
Write a concise note to `workspace/features/<slug>/research.md` (or return it inline when standalone). Sections: Findings (with file:line), Patterns, Integration points, Risks, Open questions. Keep it tight — this feeds yolo-plan, not a human report.

## Constraints
- Read-only: never edit code, never run mutating commands.
- No status files. You do not set or read any feature "status" — that is derived from git (`.claude/yolo/conventions.md`).
- Cite `file:line`; do not invent APIs.
```

- [ ] **Step 2: Verify frontmatter + that it stays read-only and cites the conventions**

Run (with `check_skill` from the File Structure section defined in your shell):
```bash
check_skill yolo-research
grep -q 'conventions.md' .claude/skills/yolo-research/SKILL.md && echo "CITES-CONVENTIONS"
grep -qi 'read-only' .claude/skills/yolo-research/SKILL.md && echo "READ-ONLY-DECLARED"
grep -q 'workspace/features/<slug>/research.md' .claude/skills/yolo-research/SKILL.md && echo "OUTPUT-PATH-OK"
```
Expected: `FRONTMATTER OK: yolo-research — …`, then `CITES-CONVENTIONS`, `READ-ONLY-DECLARED`, `OUTPUT-PATH-OK`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/yolo-research/SKILL.md
git commit -m "feat(yolo): yolo-research skill — read-only context gathering"
```

---

### Task 2: `yolo-plan` skill

**Files:**
- Create: `.claude/skills/yolo-plan/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.claude/skills/yolo-plan/SKILL.md` with exactly this content:

```markdown
---
name: yolo-plan
description: Use when you have a goal or brief and need to break it into executable, testable tasks. Produces a committed plan.md. Triggers on "make a plan", "break this into tasks", or as the planning step of yolo-feature.
---

# yolo-plan

Turn a goal into an ordered set of small, testable tasks. One task = one commit.

## Inputs
- The brief (`workspace/features/<slug>/brief.md`) and, if present, `…/research.md`.

## Procedure
1. Decompose the goal into tasks small enough that each is one focused commit (roughly 2–5 steps of work).
2. For each task define: a kebab-case `id`, `title`, `description`, the `files` it touches, a `test_spec` (the tests to write/update — required for non-scaffolding tasks), a one-line `verification`, and `depends_on` (task ids).
3. Discover the project's `lint_commands` and `test_commands` from its config (package.json scripts, Makefile, pyproject, etc.) and record them — yolo-verify reuses them.
4. Order tasks by dependency.

## Output
Write `workspace/features/<slug>/plan.md` as YAML:

​```yaml
tasks:
  - id: add-csv-export
    title: "Add CSV export endpoint"
    description: "..."
    files: ["src/export.ts"]
    test_spec: "src/export.test.ts: happy-path export + empty-dataset"
    verification: "GET /export returns text/csv"
    depends_on: []
lint_commands: ["eslint ."]
test_commands: ["npm test"]
​```

## Execution contract (consumed downstream)
- Each task is implemented test-first and committed with the trailer `YOLO-Task: <id>` (see `.claude/yolo/conventions.md`).
- Present the plan for approval before any code is written (this is the billed-work gate, unless `ux.mode: auto`).

## Constraints
- No status files; status is derived from git. You only write `plan.md`.
```

Note: the `​```yaml` fences inside the body use a zero-width joiner in this plan to avoid breaking the outer block — when you create the file, write **normal triple-backtick** ```` ```yaml ```` / ```` ``` ```` fences.

- [ ] **Step 2: Verify**

```bash
check_skill yolo-plan
grep -q 'workspace/features/<slug>/plan.md' .claude/skills/yolo-plan/SKILL.md && echo "PLAN-PATH-OK"
grep -q 'YOLO-Task: <id>' .claude/skills/yolo-plan/SKILL.md && echo "TRAILER-CITED"
grep -q 'test_spec' .claude/skills/yolo-plan/SKILL.md && echo "TEST-SPEC-OK"
# Confirm no literal zero-width artifacts leaked into the file:
grep -qP '\x{200d}' .claude/skills/yolo-plan/SKILL.md && echo "ZWJ-LEAK" || echo "NO-ZWJ"
```
Expected: `FRONTMATTER OK…`, `PLAN-PATH-OK`, `TRAILER-CITED`, `TEST-SPEC-OK`, `NO-ZWJ`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/yolo-plan/SKILL.md
git commit -m "feat(yolo): yolo-plan skill — goal to testable tasks"
```

---

### Task 3: `yolo-verify` skill

**Files:**
- Create: `.claude/skills/yolo-verify/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.claude/skills/yolo-verify/SKILL.md` with exactly this content:

```markdown
---
name: yolo-verify
description: Use to check a feature's work against its success_criteria and record the result. Produces verification.md and, on pass, the YOLO-Verified trailer. Triggers on "verify this", "does it meet the criteria", or as the verify step of yolo-feature.
---

# yolo-verify

Decide, with evidence, whether the work satisfies the brief's `success_criteria`.

## Inputs
- `workspace/features/<slug>/brief.md` (`success_criteria`), the diff `git diff <base_branch>..feature/<slug>`, and `plan.md` `lint_commands`/`test_commands`.

## Procedure
1. Run the recorded `lint_commands` and `test_commands`. Capture pass/fail and key output.
2. For EACH criterion in `success_criteria`, gather concrete evidence (a passing test, an observed behavior, a code reference). Mark it met/unmet.
3. Write `workspace/features/<slug>/verification.md`: one section per criterion with its evidence, plus the lint/test results.

## Outcome
- **All criteria met** → commit the verification file with the trailer:
  `git add workspace/features/<slug>/verification.md && git commit -m "verify: <slug>" --trailer "YOLO-Verified: true"`
- **Any criterion unmet** → write the file recording what failed, do NOT write the trailer, and report the gap so execution can resume. A feature is never "done" without `YOLO-Verified: true` (`.claude/yolo/conventions.md`).

## Constraints
- The only file you write is `verification.md`. You do not edit code.
- Verification is semantic (criteria), distinct from CI (mechanical) — yolo-finish handles CI.
```

- [ ] **Step 2: Verify**

```bash
check_skill yolo-verify
grep -q 'YOLO-Verified: true' .claude/skills/yolo-verify/SKILL.md && echo "VERIFY-TRAILER-OK"
grep -q 'workspace/features/<slug>/verification.md' .claude/skills/yolo-verify/SKILL.md && echo "VERIFY-PATH-OK"
grep -qi 'do not write the trailer' .claude/skills/yolo-verify/SKILL.md && echo "FAIL-PATH-OK"
```
Expected: `FRONTMATTER OK…`, `VERIFY-TRAILER-OK`, `VERIFY-PATH-OK`, `FAIL-PATH-OK`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/yolo-verify/SKILL.md
git commit -m "feat(yolo): yolo-verify skill — criteria check + YOLO-Verified trailer"
```

---

### Task 4: `yolo-finish` skill (finishing policy + risk classifier)

**Files:**
- Create: `.claude/skills/yolo-finish/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.claude/skills/yolo-finish/SKILL.md` with exactly this content:

```markdown
---
name: yolo-finish
description: Use when a feature is implemented and verified, to land it. Default path is PR + CI gate + auto-merge on green; fast-local is the escape hatch. Includes the risk classifier that decides auto-merge vs human review. Triggers on "ship it", "land this", "open a PR", or as the finish step of yolo-feature.
---

# yolo-finish

Land verified work. Match the rigor to the risk.

## Precondition
The branch carries `YOLO-Verified: true` (`.claude/yolo/conventions.md`). If not, run yolo-verify first.

## Choose the path (read `workspace/config.yaml` `finish.mode`)
- **fast-local** (`mode: local`, or user says throwaway/offline): merge locally —
  `git switch <base_branch> && git merge --no-ff feature/<slug> -m "merge: feature/<slug>"`.
  The condensed summary goes in the merge-commit message. No forge.
- **PR** (`mode: pr`, the default): push the branch and open a PR/MR
  (`gh pr create` / `glab mr create`). The PR description IS the summary — generated from
  the brief (what) + plan (how) + diff (the work) + verification (evidence).

## CI gate (PR path; `finish.ci`)
- `auto`: if the repo has CI, require green before merge; if it has none, fall back to the yolo-verify result as the gate.
- `require`: always demand green CI. `off`: never wait on CI.

## Risk classifier (PR path — decides auto-merge vs human review)
Default to auto-merge on green; escalate to human review on ANY trigger; when uncertain, escalate.
Compute against the diff `git diff <base_branch>..feature/<slug>` and `workspace/config.yaml` `risk.*`.

Hard triggers (always stop for the human, even in `ux.mode: auto`):
- yolo-verify did not cleanly pass, or success_criteria were vague.
- Diff touches any `risk.sensitive_paths` glob.
- Deletes/renames a public API or widely-imported symbol.

Soft triggers (escalate when crossed):
- Changed lines > `risk.max_diff_lines` OR changed files > `risk.max_diff_files`.
- A new external dependency added (package-manifest change).
- New logic shipped with no accompanying tests.

Decision:
- CI red/pending → never auto-merge (red stops; pending polls).
- CI green AND no trigger → auto-merge; set the PR body to the summary.
- CI green AND a trigger fires → stop, set the PR body, surface the specific trigger(s), wait for the human.

## Hard gate
Landing on `<base_branch>` (local merge OR PR merge) is the irreversible boundary — always explicitly confirmed. Auto-merge-on-green is the *configured* form of that consent for routine work.

## Cleanup
After a successful merge, delete the branch and remove the worktree if one was created.
```

- [ ] **Step 2: Verify the risk-classifier wiring matches config keys**

```bash
check_skill yolo-finish
for k in sensitive_paths max_diff_lines max_diff_files; do grep -q "$k" .claude/skills/yolo-finish/SKILL.md && echo "CONFIG-KEY $k OK" || echo "MISSING $k"; done
grep -q 'YOLO-Verified: true' .claude/skills/yolo-finish/SKILL.md && echo "PRECONDITION-OK"
grep -qi 'auto-merge' .claude/skills/yolo-finish/SKILL.md && grep -qi 'human review' .claude/skills/yolo-finish/SKILL.md && echo "CLASSIFIER-OK"
```
Expected: `FRONTMATTER OK…`, three `CONFIG-KEY … OK` lines, `PRECONDITION-OK`, `CLASSIFIER-OK`.

- [ ] **Step 3: Cross-check the config keys actually exist in the Plan 1 template**

```bash
python3 -c "import yaml; r=yaml.safe_load(open('.claude/yolo/templates/config.yaml'))['risk']; assert {'sensitive_paths','max_diff_lines','max_diff_files'} <= set(r); print('CONFIG-CONTRACT OK')"
```
Expected: `CONFIG-CONTRACT OK`. (If this fails, the skill and the config template disagree — fix the skill to use the real keys.)

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/yolo-finish/SKILL.md
git commit -m "feat(yolo): yolo-finish skill — finishing policy + risk classifier"
```

---

### Task 5: `yolo-feature` orchestrator skill

**Files:**
- Create: `.claude/skills/yolo-feature/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.claude/skills/yolo-feature/SKILL.md` with exactly this content:

```markdown
---
name: yolo-feature
description: Use when the user wants to build, add, or implement a feature. Captures intent, drafts a brief, confirms, then composes research → plan → execute → verify → finish. In a YOLO-initialized repo this takes precedence over generic brainstorming for feature intent.
---

# yolo-feature

The conversational entry point. You turn "I want X" into a landed, verified change.
Cheap steps run freely; billed steps are gated.

## 1. Capture intent (cheap — no confirmation needed)
- Ask a light 2-question check (skip with `--skip-qa` or `ux.mode: auto`): what the user can DO after this, and how they'd know it works.
- Derive a `slug`, `goal`, and `success_criteria`. Write `workspace/features/<slug>/brief.md` from `.claude/yolo/templates/brief.md`. Commit it (`brief: <slug>`). The brief now existing = status "planned" (`.claude/yolo/conventions.md`).

## 2. Confirm before billed work (the gate)
Show the drafted brief and the intended path. STOP and get approval before spawning any billed agent or writing code (skip only in `ux.mode: auto`).

## 3. Branch (and worktree only if needed)
`git switch -c feature/<slug>`. Create a worktree (`../.<repo>-worktrees/<slug>`) only if work will run in parallel or you need walk-away isolation (§4.7); otherwise a plain branch.

## 4. Compose the atoms
- **yolo-research** — invoke when the change is non-trivial or the codebase is unfamiliar; skip for tiny obvious changes (`--no-research`).
- **yolo-plan** — produce `plan.md`; present for approval.
- **execute** — for each task in `plan.md`, work test-first (use superpowers:test-driven-development), and commit that task with `--trailer "YOLO-Task: <id>"`. Use subagents for isolation when tasks are independent.
- **yolo-verify** — check `success_criteria`; on pass it writes the `YOLO-Verified: true` trailer.
- **yolo-finish** — land per the finishing policy + risk classifier.

## Rules
- Honor `workspace/config.yaml` `ux.mode` (interactive/guided/auto) for how much you ask.
- Store no status — every "where are we" is derived from git via yolo-status.
- Precedence: in a YOLO repo, feature intent routes here; generic brainstorming yields.
- The atoms are defined once in their own skills — invoke them, don't reimplement them here.
```

- [ ] **Step 2: Verify it composes the real atom names and honors the gate**

```bash
check_skill yolo-feature
for s in yolo-research yolo-plan yolo-verify yolo-finish; do grep -q "$s" .claude/skills/yolo-feature/SKILL.md && echo "COMPOSES $s" || echo "MISSING $s"; done
grep -q 'YOLO-Task: <id>' .claude/skills/yolo-feature/SKILL.md && echo "TASK-TRAILER-OK"
grep -qi 'confirm before billed' .claude/skills/yolo-feature/SKILL.md && echo "GATE-OK"
grep -qi 'precedence' .claude/skills/yolo-feature/SKILL.md && echo "PRECEDENCE-OK"
```
Expected: `FRONTMATTER OK…`, four `COMPOSES …` lines, `TASK-TRAILER-OK`, `GATE-OK`, `PRECEDENCE-OK`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/yolo-feature/SKILL.md
git commit -m "feat(yolo): yolo-feature orchestrator skill — conversational entry"
```

---

### Task 6: Cross-skill consistency check

**Files:**
- Create: `docs/superpowers/plans/acceptance/methodology-skills-consistency.md`

- [ ] **Step 1: Write the consistency acceptance check**

Create `docs/superpowers/plans/acceptance/methodology-skills-consistency.md` with exactly this content:

````markdown
# Acceptance: Methodology skills consistency

Confirms all five skills are well-formed and agree on the Plan 1 contracts. Run from repo root.

```sh
set -e
fail=0
for s in yolo-research yolo-plan yolo-verify yolo-finish yolo-feature; do
  f=".claude/skills/$s/SKILL.md"
  test -f "$f" || { echo "MISSING $f"; fail=1; continue; }
  head -1 "$f" | grep -qx -- '---' || { echo "NO-FRONTMATTER $s"; fail=1; }
  grep -q "name: $s" "$f" || { echo "NAME-MISMATCH $s"; fail=1; }
done
# Contract strings present in the skills that use them:
grep -q 'YOLO-Task: <id>' .claude/skills/yolo-plan/SKILL.md || { echo "plan missing task trailer"; fail=1; }
grep -q 'YOLO-Verified: true' .claude/skills/yolo-verify/SKILL.md || { echo "verify missing verified trailer"; fail=1; }
grep -q 'workspace/features/<slug>/brief.md' .claude/skills/yolo-feature/SKILL.md || { echo "feature missing brief path"; fail=1; }
# Config keys referenced by yolo-finish must exist in the template:
python3 -c "import yaml; r=yaml.safe_load(open('.claude/yolo/templates/config.yaml'))['risk']; assert {'sensitive_paths','max_diff_lines','max_diff_files'} <= set(r)" || { echo "config/finish drift"; fail=1; }
test "$fail" = 0 && echo "ALL-CONSISTENT" || { echo "INCONSISTENT"; exit 1; }
```

Expected final line: `ALL-CONSISTENT`.
````

- [ ] **Step 2: Run it**

```bash
sed -n '/^```sh$/,/^```$/p' docs/superpowers/plans/acceptance/methodology-skills-consistency.md | sed '1d;$d' | bash
```
Expected output: `ALL-CONSISTENT`.

- [ ] **Step 3: Manual behavioral check (documented, not automated)**

In a fresh Claude Code session in this repo, type a plain feature request (e.g., "I want users to be able to export their data as CSV"). Confirm `yolo-feature` activates (it announces itself), drafts a brief at `workspace/features/export-csv/brief.md`, and **stops for confirmation before** writing code. Record the outcome in the commit message. (This verifies trigger-by-description, which no shell check can prove.)

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/plans/acceptance/methodology-skills-consistency.md
git commit -m "test(yolo): methodology skills consistency check"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** §4.4 skill table → Tasks 1–5 (one per skill); composition graph → Task 5 (yolo-feature invokes the four atoms) + Task 6 (verifies the composition names). §4.5 conversational entry + precedence → Task 5 (`description` + Rules). §4.6/§4.6.1 finishing + risk classifier → Task 4 (hard/soft triggers, decision order, config keys). Execution-is-not-a-skill → Task 5 (execute step lives in the orchestrator, uses TDD + `YOLO-Task` trailer; no `yolo-execute` file).

**Placeholder scan:** Every SKILL.md body is given in full. The one fence-escaping caveat (Task 2's inner ```yaml example) is called out explicitly with the corrective instruction and a `NO-ZWJ` guard check — not a placeholder.

**String consistency:** brief/plan/verification paths, `feature/<slug>`, `YOLO-Task: <id>`, `YOLO-Verified: true`, and `risk.{sensitive_paths,max_diff_lines,max_diff_files}` are identical across Tasks 1–5 and re-asserted in Task 6. Task 4 Step 3 and Task 6 both cross-check the skill's config keys against the real Plan 1 `config.yaml` template, so skill/config drift fails loudly.

**Out of scope (later plans):** `yolo-roadmap`/`intake`/`status`/`decide`/`init` and the CLAUDE.md routing block (Plan 3); deletion of `commands/yolo/`, `workflows/`, `agents/`, `spec.md` (Plan 4).
