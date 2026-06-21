# YOLO Demolition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the v2 heavyweight state machine — the 858-line `spec.md`, the agent prompts, the workflows, and the `/yolo:*` slash commands — now that the reasoning-first skills (Plans 1–3) fully replace them, leaving a clean codebase whose only YOLO surface is the skills + `conventions.md` + `templates/`.

**Architecture:** Pure deletion, gated by safety. Each removal is preceded by a grep proving no live (Plan 1–3) artifact references the target, then `git rm`, then commit. A final integrity pass re-runs every acceptance check from Plans 1–3 to prove the new system still stands after the old one is gone.

**Tech Stack:** git, shell. No new files except acceptance output.

**Prerequisite:** Plans 1, 2, and 3 are committed and their acceptance checks pass. This plan is **destructive and terminal** — do not start it until the new system is verified working (ideally after Plan 3 Task 6's behavioral trigger check PASSes).

**Scope note:** This demolishes the v2 surface **in this framework repo only**. Consumer projects still on v2 (e.g. `../ai-followups`, `../receptionist`) are NOT touched — migrating them is a separate effort (spec §8: "No migration tooling … in the first cut"). Everything deleted here remains recoverable from git history.

**Targets (verified present at plan-authoring time):**
- `.claude/yolo/spec.md` (v2 spec)
- `.claude/yolo/agents/` (decide, execute, feature-breakdown, plan, research, verify)
- `.claude/yolo/workflows/` (feature, init, intake, release, status)
- `.claude/commands/yolo/` (decide, feature, help, init, intake, release, status)

**What survives:** `.claude/yolo/conventions.md`, `.claude/yolo/templates/`, `.claude/skills/yolo-*`, `workspace/`, `.claude/settings.json` (reviewed, not deleted), `docs/`.

---

## File Structure

No files created except `docs/superpowers/plans/acceptance/post-demolition-integrity.md`. All other changes are deletions of the four target paths above, plus a possible light edit to `.claude/settings.json` (Task 6).

---

### Task 1: Pre-demolition safety audit (non-destructive)

Prove the new system does not reference anything we are about to delete.

- [ ] **Step 1: Confirm the new system is intact**

```bash
ls .claude/skills/ | sort
test -f .claude/yolo/conventions.md && echo "CONVENTIONS-OK"
ls .claude/yolo/templates/
```
Expected: ten `yolo-*` skill dirs listed (yolo-decide, yolo-feature, yolo-finish, yolo-init, yolo-intake, yolo-plan, yolo-research, yolo-roadmap, yolo-status, yolo-verify), `CONVENTIONS-OK`, and the templates (`brief.md`, `claude-routing-block.md`, `config.yaml`).

- [ ] **Step 2: Prove no live artifact references the doomed paths**

```bash
echo "--- references from skills/conventions/templates/CLAUDE.md to deleted paths ---"
grep -rnE 'yolo/spec\.md|yolo/agents/|yolo/workflows/|commands/yolo/' \
  .claude/skills .claude/yolo/conventions.md .claude/yolo/templates CLAUDE.md 2>/dev/null \
  && echo "FOUND-LIVE-REFS (investigate before deleting)" || echo "NO-LIVE-REFS"
```
Expected: `NO-LIVE-REFS`. If any reference is found, STOP — fix the referencing skill first (it should cite `conventions.md`/`templates/`, never the v2 files).

- [ ] **Step 3: Record the demolition manifest**

```bash
git ls-files .claude/yolo/spec.md .claude/yolo/agents .claude/yolo/workflows .claude/commands/yolo | tee /tmp/yolo-demolition-manifest.txt | wc -l
```
Expected: a non-zero count (the tracked v2 files). This is informational — no commit.

---

### Task 2: Delete the v2 agent prompts

- [ ] **Step 1: Re-confirm nothing live references agents/**

```bash
grep -rn 'yolo/agents/' .claude/skills .claude/yolo/conventions.md CLAUDE.md 2>/dev/null && echo "STOP-REFS" || echo "SAFE"
```
Expected: `SAFE`.

- [ ] **Step 2: Remove**

```bash
git rm -rf .claude/yolo/agents
```
Expected: git lists the six removed agent files.

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(yolo): remove v2 agent prompts (replaced by skills)"
```

---

### Task 3: Delete the v2 workflows

- [ ] **Step 1: Re-confirm nothing live references workflows/**

```bash
grep -rn 'yolo/workflows/' .claude/skills .claude/yolo/conventions.md CLAUDE.md 2>/dev/null && echo "STOP-REFS" || echo "SAFE"
```
Expected: `SAFE`.

- [ ] **Step 2: Remove**

```bash
git rm -rf .claude/yolo/workflows
```
Expected: git lists the five removed workflow files.

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(yolo): remove v2 workflows (replaced by skills)"
```

---

### Task 4: Delete the v2 slash commands

Note: the new model is skills + natural-language routing (the CLAUDE.md block). The old `/yolo:*` commands invoke the now-deleted workflows, so they must go. Thin escape-hatch commands that merely invoke a skill can be re-added later as a separate additive change — out of scope here.

- [ ] **Step 1: Re-confirm nothing live references commands/yolo/**

```bash
grep -rn 'commands/yolo/' .claude/skills .claude/yolo/conventions.md CLAUDE.md 2>/dev/null && echo "STOP-REFS" || echo "SAFE"
```
Expected: `SAFE`.

- [ ] **Step 2: Remove**

```bash
git rm -rf .claude/commands/yolo
```
Expected: git lists the seven removed command files.

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(yolo): remove v2 /yolo:* slash commands (replaced by skills + routing)"
```

---

### Task 5: Delete the v2 spec

The v2 `spec.md` is superseded by `.claude/yolo/conventions.md` (the live contract) and the design doc `docs/superpowers/specs/2026-06-21-yolo-reasoning-first-redesign.md` (the rationale). Its heavy detail (status machine, intent_qa schema, locks) is intentionally dropped per the redesign; it remains in git history if ever needed.

- [ ] **Step 1: Re-confirm nothing live references spec.md**

```bash
grep -rn 'yolo/spec\.md' .claude/skills .claude/yolo/conventions.md .claude/yolo/templates CLAUDE.md 2>/dev/null && echo "STOP-REFS" || echo "SAFE"
```
Expected: `SAFE`. (Mentions inside `docs/` are historical and allowed — they are not live framework files.)

- [ ] **Step 2: Remove**

```bash
git rm -f .claude/yolo/spec.md
```

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(yolo): remove v2 spec.md (superseded by conventions.md + design doc)"
```

---

### Task 6: Review `.claude/settings.json` for stale YOLO references (light)

`settings.json` may carry permission/allow entries that existed for the v2 workflows (team tools, `/yolo:*` invocations). Leaving tool permissions is harmless; removing entries that name the deleted commands keeps it tidy. This task is conservative — only remove entries that explicitly reference deleted paths.

- [ ] **Step 1: Inspect**

```bash
grep -nE 'yolo|TeamCreate|TaskCreate|TeamDelete' .claude/settings.json || echo "NO-YOLO-ENTRIES"
```

- [ ] **Step 2: Decide and (only if needed) edit**

If any entry literally references a deleted command path (e.g., a permission string mentioning `commands/yolo/`), remove just that entry, keeping the JSON valid. Generic tool permissions (TeamCreate/TaskCreate/etc.) MAY be kept — the skills still use subagents. If nothing references deleted paths, make no change and skip to Step 4.

- [ ] **Step 3: Validate JSON if edited**

```bash
python3 -c "import json; json.load(open('.claude/settings.json')); print('JSON-OK')"
```
Expected: `JSON-OK`.

- [ ] **Step 4: Commit (only if changed)**

```bash
git add .claude/settings.json && git commit -m "chore(yolo): drop settings entries for removed v2 commands" || echo "no changes"
```

---

### Task 7: Post-demolition integrity check

Prove the new system still stands with the old one gone.

**Files:**
- Create: `docs/superpowers/plans/acceptance/post-demolition-integrity.md`

- [ ] **Step 1: Write the integrity check**

Create `docs/superpowers/plans/acceptance/post-demolition-integrity.md` with exactly this content:

````markdown
# Acceptance: Post-demolition integrity

Run from repo root. Proves the v2 surface is gone and the v-next surface is intact.

```sh
set -e
fail=0
# v2 surface is gone:
for p in .claude/yolo/spec.md .claude/yolo/agents .claude/yolo/workflows .claude/commands/yolo; do
  test -e "$p" && { echo "STILL-PRESENT $p"; fail=1; }
done
# v-next surface is present:
for s in yolo-research yolo-plan yolo-verify yolo-finish yolo-feature \
         yolo-status yolo-roadmap yolo-intake yolo-decide yolo-init; do
  test -f ".claude/skills/$s/SKILL.md" || { echo "MISSING-SKILL $s"; fail=1; }
done
test -f .claude/yolo/conventions.md || { echo "MISSING conventions.md"; fail=1; }
grep -q 'YOLO:routing-block start' CLAUDE.md || { echo "routing block gone"; fail=1; }
# no dangling live references to deleted paths:
grep -rqE 'yolo/spec\.md|yolo/agents/|yolo/workflows/|commands/yolo/' \
  .claude/skills .claude/yolo/conventions.md .claude/yolo/templates CLAUDE.md 2>/dev/null \
  && { echo "DANGLING-REF"; fail=1; } || true
test "$fail" = 0 && echo "INTEGRITY-OK" || { echo "INTEGRITY-FAIL"; exit 1; }
```

Expected final line: `INTEGRITY-OK`.
````

- [ ] **Step 2: Run it, plus re-run the prior acceptance checks**

```bash
sed -n '/^```sh$/,/^```$/p' docs/superpowers/plans/acceptance/post-demolition-integrity.md | sed '1d;$d' | bash
sed -n '/^```sh$/,/^```$/p' docs/superpowers/plans/acceptance/methodology-skills-consistency.md | sed '1d;$d' | bash
sed -n '/^```sh$/,/^```$/p' docs/superpowers/plans/acceptance/standalone-acts-consistency.md | sed '1d;$d' | bash
sed -n '/^```sh$/,/^```$/p' docs/superpowers/plans/acceptance/foundation-git-roundtrip.md | sed '1d;$d' | bash
```
Expected, in order: `INTEGRITY-OK`, `ALL-CONSISTENT`, `ALL-CONSISTENT`, then the five foundation lines (`planned`/`in-progress`/`add-csv-export`/`verified`/`done`).

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/acceptance/post-demolition-integrity.md
git commit -m "test(yolo): post-demolition integrity check — v-next intact, v2 gone"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** §6 "Deleted vs kept" — the deleted list (state machine, release entity, locks, retry counters) is realized by removing the files that *encode* it: `spec.md` (the schema), `workflows/` (the lifecycle), `agents/` (the v2 prompts), `commands/yolo/` (the entry points). The kept list (conventions, skills, decide, workspace) is asserted present by Task 7.

**Placeholder scan:** No placeholders. Every deletion has an exact `git rm`, every check an exact command and expected output. Task 6 is deliberately conditional (edit only if a stale reference exists) with a JSON-validity gate.

**Safety:** Each deletion is gated by a `SAFE`/`STOP-REFS` grep against the live surface, Task 1 audits before anything is removed, and Task 7 re-runs all four prior+new acceptance checks so a mistaken deletion fails loudly. Everything is recoverable from git history. Consumer-project migration is explicitly out of scope.

**Consistency:** The target path list is identical in the Targets section, every per-task grep, and Task 7's integrity check. The skill list in Task 7 matches the ten skills built across Plans 2–3.
