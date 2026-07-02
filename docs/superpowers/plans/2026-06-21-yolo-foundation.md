# YOLO Foundation Implementation Plan

> **Status: COMPLETED 2026-06-21 — historical record, not current instructions.** The live contract is `.claude/yolo/conventions.md` and the `yolo-*` skills.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the durable contracts of the reasoning-first YOLO — directory layout, `config.yaml`, the feature brief format, and the git-as-truth conventions (commit-trailer schema + derived-status rules) — so the methodology skills in later plans have a fixed foundation to build on.

**Architecture:** YOLO is a pure-markdown framework with **no code or test stack by design** (the whole point of the redesign is "maximum model reasoning, minimum framework"). This plan therefore produces *contracts* (templates + a conventions reference), and each task is verified by **acceptance checks** — YAML validity, an end-to-end git round-trip with expected output, and consistency greps — not unit tests. State is never stored as a tracked field; it is **derived from git** at read time.

**Tech Stack:** Markdown, YAML, git, shell (`bash`/`zsh`), `python3` (YAML lint only — already on macOS). No new runtime dependency is introduced.

**This plan resolves design open questions (see spec §9):**
- **Q1 trailer schema** → §"Conventions" below: `YOLO-Task: <task-id>` per task commit; `YOLO-Verified: true` on the verification commit; **plus** a committed `verification.md` (trailer = greppable machine signal, file = human-readable audit). Both.
- **Q2 brief location** → `workspace/features/<slug>/brief.md` (folder-per-feature, so `plan.md` + `verification.md` colocate beside the brief).
- **Q3 config field set** → Task 1 defines the minimal, non-drifting set.
- Q4 (CLAUDE.md routing wording) is intentionally deferred to Plan 3 (Standalone acts + routing).

**Spec reference:** `docs/superpowers/specs/2026-06-21-yolo-reasoning-first-redesign.md` (§4.1 unit of work, §4.2 git-as-truth, §4.3 intake shelf, §4.6.1 risk config, §5 thin spine).

---

## File Structure

Files created by this plan and their single responsibility:

- `.claude/yolo/templates/config.yaml` — the canonical `config.yaml` template copied into `workspace/` at init. Genuine config only (models, base branch, finish policy, risk thresholds, ux mode). **No tracked state.**
- `.claude/yolo/templates/brief.md` — the canonical feature-brief template (frontmatter schema + body).
- `.claude/yolo/conventions.md` — the git-as-truth reference: branch/worktree naming, the commit-trailer schema, and the rules for *deriving* feature status from git. This is the single source every later skill cites; it must be unambiguous.
- `workspace/.gitkeep` — ensures the tracked `workspace/` root exists (the project's durable spine; never git-ignored).
- `workspace/intake/.gitkeep` — the project-level intake reference shelf (spec §4.3), owned by no release.
- `workspace/features/.gitkeep` — the home for atomic feature folders.
- `docs/superpowers/plans/acceptance/foundation-git-roundtrip.md` — a runnable walkthrough proving the conventions compute correctly against real git (the foundation's "integration test").

No existing files are modified or deleted in this plan. The old `.claude/yolo/spec.md`, `workflows/`, `agents/`, and `commands/yolo/` are left untouched until Plan 4 (Demolition), so nothing breaks mid-migration.

---

## Conventions established by this plan (the contract)

Later plans depend on these exact strings — do not paraphrase them when implementing skills.

**Branch / worktree naming**
- Feature branch: `feature/<slug>` (e.g., `feature/export-csv`).
- Worktree (only when isolation is needed, spec §4.7): `../.<repo-name>-worktrees/<slug>`.

**Commit trailers** (Git-native state; see git `--trailer` / `interpret-trailers`)
- `YOLO-Task: <task-id>` — one per completed plan task, on that task's commit. `<task-id>` is the kebab-case id from `plan.md`.
- `YOLO-Verified: true` — on the single verification commit, written by `yolo-verify` once `success_criteria` pass.

**Derived status** (never stored; computed from git + files at read time)
- `planned` — `workspace/features/<slug>/brief.md` exists **and** branch `feature/<slug>` does **not** exist.
- `in-progress` — branch `feature/<slug>` exists **and** is not merged into `base_branch`.
- `done` — branch `feature/<slug>` is merged into `base_branch` (`git branch --merged`), **or** the branch carries a `YOLO-Verified: true` trailer and a committed `verification.md`.
- Completed tasks for a feature: `git log <base>..feature/<slug> --format=%(trailers:key=YOLO-Task,valueonly)` (non-empty lines).

---

### Task 1: `config.yaml` template (minimal, non-drifting config)

**Files:**
- Create: `.claude/yolo/templates/config.yaml`

- [ ] **Step 1: Write the config template**

Create `.claude/yolo/templates/config.yaml` with exactly this content:

```yaml
# YOLO configuration — genuine config only. NEVER tracked state.
# Copied into workspace/config.yaml by `yolo-init`. Status lives in git, not here.

project:
  name: ""                 # set at init (repo dir name)
  base_branch: "main"      # merge target; init auto-detects "master" if "main" is absent

agents:                    # model tier per methodology skill (spec §4.4)
  research: opus
  plan: opus
  execute: sonnet
  verify: haiku
  roadmap: opus
  decide: opus

finish:                    # finishing policy (spec §4.6)
  mode: pr                 # pr | local  — default landing path
  ci: auto                 # auto = gate on CI if configured, else fall back to yolo-verify
                           # require = always demand green CI; off = never wait on CI
  auto_merge_on_green: true

risk:                      # risk classifier inputs (spec §4.6.1)
  sensitive_paths:
    - "**/auth/**"
    - "**/billing/**"
    - "**/payment*/**"
    - "**/migrations/**"
    - "**/*.env*"
    - "**/secrets/**"
    - "Dockerfile"
    - "**/deploy/**"
    - "**/.github/workflows/**"
    - ".gitlab-ci.yml"
  max_diff_lines: 400
  max_diff_files: 15

ux:
  mode: interactive        # interactive | guided | auto
```

- [ ] **Step 2: Verify it is valid YAML and contains no tracked-state fields**

Run:
```bash
python3 -c "import yaml,sys; d=yaml.safe_load(open('.claude/yolo/templates/config.yaml')); print('keys:', sorted(d)); assert set(d)=={'project','agents','finish','risk','ux'}, d; print('OK')"
```
Expected output: `keys: ['agents', 'finish', 'project', 'risk', 'ux']` then `OK`.

- [ ] **Step 3: Verify no status/lifecycle words leaked into config** (guards the "config never holds state" invariant)

Run:
```bash
grep -Ei 'status|pending|in_progress|completed|run_active|retry|lock' .claude/yolo/templates/config.yaml && echo "LEAK" || echo "CLEAN"
```
Expected output: `CLEAN`.

- [ ] **Step 4: Commit**

```bash
git add .claude/yolo/templates/config.yaml
git commit -m "feat(yolo): config.yaml template — config-only, no tracked state"
```

---

### Task 2: Feature brief template (`brief.md`)

**Files:**
- Create: `.claude/yolo/templates/brief.md`

- [ ] **Step 1: Write the brief template**

Create `.claude/yolo/templates/brief.md` with exactly this content:

```markdown
---
slug: ""                   # kebab-case; defines branch feature/<slug> and folder name
goal: ""                   # one sentence: what the user can do after this ships
success_criteria: []       # observable, checkable behaviors — yolo-verify checks these
milestone: null            # optional grouping label (replaces "release"); e.g. "mvp"
depends_on: []             # optional NN-slug/slug list; honored by the model, no DAG machine
intake_refs: []            # optional pointers into workspace/intake/<source>/
created_at: ""             # ISO 8601 UTC
---

# <Title>

<Free-form context: the motivation, constraints, links, and any cited intake.
This body is for humans and for the research/plan skills; it has no schema.>
```

- [ ] **Step 2: Verify the frontmatter is valid YAML with exactly the expected keys**

Run:
```bash
python3 - <<'PY'
import yaml
text = open('.claude/yolo/templates/brief.md').read()
fm = text.split('---',2)[1]
d = yaml.safe_load(fm)
assert set(d) == {'slug','goal','success_criteria','milestone','depends_on','intake_refs','created_at'}, sorted(d)
assert d['success_criteria'] == [] and d['depends_on'] == [] and d['intake_refs'] == []
print('OK', sorted(d))
PY
```
Expected output: `OK ['created_at', 'depends_on', 'goal', 'intake_refs', 'milestone', 'slug', 'success_criteria']`.

- [ ] **Step 3: Commit**

```bash
git add .claude/yolo/templates/brief.md
git commit -m "feat(yolo): feature brief template — the atomic unit of work"
```

---

### Task 3: Git-as-truth conventions reference (`conventions.md`)

**Files:**
- Create: `.claude/yolo/conventions.md`

- [ ] **Step 1: Write the conventions reference**

Create `.claude/yolo/conventions.md` with exactly this content:

````markdown
# YOLO Git-as-Truth Conventions

YOLO stores **no tracked status**. Feature state is **derived** from git and on-disk
artifacts at the moment it is asked. This file is the single source of truth for the
naming, trailers, and derivation rules every `yolo-*` skill relies on. Do not paraphrase
these strings elsewhere — cite this file.

## The unit of work

A feature = a **brief** (`workspace/features/<slug>/brief.md`) + a **branch**
(`feature/<slug>`). Alongside the brief, as the work progresses:
- `plan.md` — tasks (written by `yolo-plan`)
- `verification.md` — evidence (written by `yolo-verify`)

## Naming

- Branch: `feature/<slug>`
- Worktree (only when isolation is needed): `../.<repo-name>-worktrees/<slug>`
- Milestone grouping (optional, replaces "release"): a `milestone:` value in the brief,
  and at ship time an annotated git tag and/or a forge milestone.

## Commit trailers

Append with `git commit --trailer` (or write directly in the message footer):

| Trailer | Where | Meaning |
|---|---|---|
| `YOLO-Task: <task-id>` | the commit completing a plan task | that `plan.md` task is done (`<task-id>` is its kebab-case id) |
| `YOLO-Verified: true`  | the single verification commit | `success_criteria` passed (`yolo-verify`) |

Trailers are the **greppable machine signal**; `verification.md` is the **human-readable
audit**. Both are written — neither alone is sufficient. Caveat: `rebase`/`squash` can
drop trailers; uncommitted work never counts.

## Deriving status (no stored field)

Given a feature `<slug>` and the configured `base_branch`:

- **planned** — `workspace/features/<slug>/brief.md` exists AND `feature/<slug>` does not.
- **in-progress** — `feature/<slug>` exists AND is not merged into `base_branch`.
- **done** — `feature/<slug>` is merged into `base_branch`
  (`git branch --merged <base_branch>` lists it), OR the branch tip carries
  `YOLO-Verified: true` with a committed `verification.md`.

Completed tasks for an in-progress feature:

```sh
git log <base_branch>..feature/<slug> \
  --format='%(trailers:key=YOLO-Task,valueonly)' | sed '/^$/d'
```

Verified check:

```sh
git log <base_branch>..feature/<slug> \
  --format='%(trailers:key=YOLO-Verified,valueonly)' | grep -qx true
```

## Why derived beats tracked

A computed view cannot drift, so there is nothing to reconcile. This is why the v2
`state.yaml`/`release.yaml`/`feature.yaml` status machine, its locks, TOCTOU guards,
and retry counters are deleted (Plan 4).
````

- [ ] **Step 2: Verify the trailer strings are exact and consistent with the templates**

Run:
```bash
grep -c 'YOLO-Task:' .claude/yolo/conventions.md && grep -c 'YOLO-Verified: true' .claude/yolo/conventions.md
```
Expected output: a number `>= 2` on the first line and `>= 2` on the second (the strings appear in the table and the derivation examples).

- [ ] **Step 3: Verify the brief path string matches Task 2's decision (no contradictory paths)**

Run:
```bash
grep -q 'workspace/features/<slug>/brief.md' .claude/yolo/conventions.md && echo "PATH-OK"
grep -Eq 'releases/|release\.yaml|state\.yaml' .claude/yolo/conventions.md && echo "STALE-REF" || echo "NO-STALE-REF"
```
Expected output: `PATH-OK` then `NO-STALE-REF`. (The only allowed mention of `state.yaml`/`release.yaml` is the final "Why derived beats tracked" paragraph, which names them as *deleted* — if `STALE-REF` prints, confirm it is only that sentence; otherwise fix.)

- [ ] **Step 4: Commit**

```bash
git add .claude/yolo/conventions.md
git commit -m "feat(yolo): git-as-truth conventions — trailers + derived status"
```

---

### Task 4: Scaffold the durable `workspace/` spine

**Files:**
- Create: `workspace/.gitkeep`
- Create: `workspace/features/.gitkeep`
- Create: `workspace/intake/.gitkeep`

- [ ] **Step 1: Create the tracked directory spine**

Run:
```bash
mkdir -p workspace/features workspace/intake
touch workspace/.gitkeep workspace/features/.gitkeep workspace/intake/.gitkeep
```

- [ ] **Step 2: Verify `workspace/` is NOT git-ignored** (the spine must survive across branches/worktrees — see global rule about `.planning`/`workspace`)

Run:
```bash
git check-ignore workspace/ workspace/features/ workspace/intake/ ; echo "exit=$?"
```
Expected output: no paths printed and `exit=1` (git-check-ignore exits non-zero when nothing is ignored). If any path prints, remove the matching rule from `.gitignore`.

- [ ] **Step 3: Verify the spine is exactly three tracked placeholders**

Run:
```bash
git add workspace && git status --porcelain workspace
```
Expected output (order may vary):
```
A  workspace/.gitkeep
A  workspace/features/.gitkeep
A  workspace/intake/.gitkeep
```

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(yolo): scaffold durable workspace/ spine (features + intake shelf)"
```

---

### Task 5: End-to-end git round-trip acceptance check

This is the foundation's integration test: it proves the Task 3 conventions actually
derive correct status against real git, using a throwaway repo so it touches nothing real.

**Files:**
- Create: `docs/superpowers/plans/acceptance/foundation-git-roundtrip.md`

- [ ] **Step 1: Write the acceptance walkthrough**

Create `docs/superpowers/plans/acceptance/foundation-git-roundtrip.md` with exactly this content:

````markdown
# Acceptance: Foundation git round-trip

Proves the git-as-truth conventions (`.claude/yolo/conventions.md`) derive correct
status. Run top-to-bottom in a scratch repo; every command's expected output is shown.

```sh
set -e
TMP=$(mktemp -d); cd "$TMP"
git init -q -b main
git config user.email t@t.test; git config user.name test
git commit -q --allow-empty -m "init"

# 1) planned: brief exists, no branch
mkdir -p workspace/features/export-csv
printf -- '---\nslug: export-csv\ngoal: export data as csv\nsuccess_criteria: ["downloads a .csv"]\nmilestone: null\ndepends_on: []\nintake_refs: []\ncreated_at: 2026-06-21T00:00:00Z\n---\n# Export CSV\n' > workspace/features/export-csv/brief.md
git add . && git commit -q -m "brief: export-csv"
git branch --list feature/export-csv | grep -q . && echo "BRANCH" || echo "planned"     # -> planned

# 2) in-progress: branch with a task commit carrying a trailer
git switch -q -c feature/export-csv
echo "col,val" > export.csv
git add export.csv
git commit -q -m "feat: add csv export" --trailer "YOLO-Task: add-csv-export"
git switch -q main
git branch --merged main | grep -qx '  feature/export-csv' && echo "done" || echo "in-progress"   # -> in-progress
git log main..feature/export-csv --format='%(trailers:key=YOLO-Task,valueonly)' | sed '/^$/d'      # -> add-csv-export

# 3) verify: trailer + verification.md
git switch -q feature/export-csv
echo "verified: criteria met" > workspace/features/export-csv/verification.md
git add workspace/features/export-csv/verification.md
git commit -q -m "verify: export-csv" --trailer "YOLO-Verified: true"
git log main..feature/export-csv --format='%(trailers:key=YOLO-Verified,valueonly)' | grep -qx true && echo "verified"   # -> verified

# 4) done: merge to base
git switch -q main
git merge -q --no-ff feature/export-csv -m "merge: feature/export-csv"
git branch --merged main | grep -q 'feature/export-csv' && echo "done" || echo "NOT-DONE"   # -> done

cd / && rm -rf "$TMP"
```

Expected printed lines, in order: `planned`, `in-progress`, `add-csv-export`,
`verified`, `done`.
````

- [ ] **Step 2: Actually run the walkthrough and confirm the derived states**

Run:
```bash
bash docs/superpowers/plans/acceptance/foundation-git-roundtrip.md 2>/dev/null || \
sed -n '/^```sh$/,/^```$/p' docs/superpowers/plans/acceptance/foundation-git-roundtrip.md | sed '1d;$d' | bash
```
Expected output (exactly, in order):
```
planned
in-progress
add-csv-export
verified
done
```
If any line differs, the conventions in Task 3 and the real git behavior disagree — fix `conventions.md` (or the trailer syntax) until they match. Do not proceed until this passes.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/acceptance/foundation-git-roundtrip.md
git commit -m "test(yolo): foundation git round-trip acceptance check"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** §4.1 unit-of-work → Tasks 2,3,5. §4.2 git-as-truth (trailers, derived status) → Tasks 3,5. §4.3 intake shelf → Task 4. §4.6.1 risk config → Task 1. §5 thin spine (config + git + workspace) → Tasks 1,4. Open questions Q1/Q2/Q3 → resolved in header + Tasks 1–3. (Q4 CLAUDE.md routing → deferred to Plan 3, by design.)

**Placeholder scan:** No "TBD/TODO/handle edge cases" — every template and reference file is given in full; every verification step has an exact command and expected output.

**Type/string consistency:** Trailer strings `YOLO-Task:` and `YOLO-Verified: true`, branch pattern `feature/<slug>`, and brief path `workspace/features/<slug>/brief.md` are identical across Tasks 2, 3, and 5 and the header. The acceptance walkthrough (Task 5) exercises the exact strings from `conventions.md` (Task 3).

**Out of scope (later plans):** the `yolo-*` skills (Plan 2), CLAUDE.md routing + standalone-act skills (Plan 3), deletion of `spec.md`/`workflows/`/`agents/`/`commands/yolo/` (Plan 4).
