# YOLO CLI Scripts Reference

These scripts work standalone — no .planning/ directory or YOLO workflow required.
Each script can be used independently in any git repository.

## commit.sh

**Purpose:** Prefix-enforced git commit with test integrity sensors.

**Usage:**
```bash
commit.sh task <N> "<message>" [--repo <path>] [--stage] [--json] [--allow-test-reduction]
commit.sh fix  <N> "<message>" [--repo <path>] [--stage] [--json]
commit.sh wip  ["<message>"]   [--repo <path>] [--stage]
commit.sh revert ["<message>"] [--repo <path>] [--stage]
commit.sh squash "<message>"   [--repo <path>] [--stage]
```

**What it detects (as warnings, not blockers):**
- Test function count decrease in modified test files
- Skip/disable markers added (test.skip, @pytest.mark.skip, etc.)
- Test files deleted entirely

**Flags:**
- `--json` — output structured JSON instead of human-readable warnings
- `--stage` — run `git add -A` before committing
- `--allow-test-reduction` — suppress test integrity warnings
- `--repo <path>` — operate on a different repository

**Exit codes:** 0 = committed (may have warnings), 1 = structural error (bad prefix, missing args)

**Standalone use:** Works in any git repo. No .planning/ needed.

---

## validate-plan.sh

**Purpose:** Plan quality sensor — checks task count, description length, test coverage.

**Usage:**
```bash
validate-plan.sh <feature-file> [--no-test-suite] [--json]
```

**What it detects:**
- Errors (exit 1): No plan section, 0 tasks, 1 task (min 2), empty test annotations
- Warnings (exit 0): >12 tasks, >50% test:none, <20 word descriptions, directory paths in files

**Flags:**
- `--json` — structured JSON output
- `--no-test-suite` — skip test coverage checks

**Standalone use:** Works on any markdown file with a `## Plan` section containing numbered checkbox tasks.

---

## reconcile.sh

**Purpose:** Bidirectional reconciliation between plan checkboxes and git commit evidence.

**Usage:**
```bash
reconcile.sh <feature-file> [<branch>] [--apply|--fix] [--repo <path>]
```

**What it does:**
- Reads `[task-N]` and `[fix-N]` commits from git log
- Compares against plan checkboxes in the feature file
- Detects drift in both directions (checked but no commit, committed but unchecked)
- Detects orphan commits (commits for tasks not in the plan)
- Derives current workflow step (think/plan/do/check/ship/done)

**Flags:**
- `--apply` — update feature file to match git evidence (git wins). `--fix` is a deprecated alias.
- `--repo <path>` — operate on a different repository

**Exit codes:** 0 = no drift, 1 = refused (rebase/merge/bisect in progress), 2 = drift detected (read-only mode without --apply)

**Standalone use:** Works on any markdown file with YAML frontmatter (branch field) and a `## Plan` section.

---

## verify-commit.sh

**Purpose:** Compare agent's claimed file changes against actual git diff.

**Usage:**
```bash
verify-commit.sh <task-N> <files-changed> [--repo <path>] [--commit-hash <hash>] [--branch <branch>] [--allow-test-reduction]
```

**What it detects (as warnings):**
- Unexpected files changed (not in agent's claim)
- Claimed files not actually changed
- Test count decrease in the commit
- Skip markers added
- Thin commits (0 files changed)

**Exit codes:** 0 = verified, 1 = warnings found

**Standalone use:** Works in any git repo with conventional commit messages.

---

## run-tests.sh

**Purpose:** Execute test and lint commands from a feature file's YAML frontmatter.

**Usage:**
```bash
run-tests.sh <feature-file> [--repo <path>] [--tail <N>]
```

**What it does:**
- Parses `lint_commands` and `test_commands` arrays from YAML frontmatter
- Executes each command, captures output and exit codes
- Truncates output to last N lines (default 200)

**Exit codes:** 0 = all pass, 1 = any failure

**Standalone use:** Works on any file with YAML frontmatter containing `lint_commands` and/or `test_commands` arrays.

---

## Hook Scripts

### hook-pre-bash.sh

**Purpose:** PreToolUse hook — blocks destructive git operations.

**Blocked commands:** git push, git reset --hard, git clean -f, git checkout ., git restore ., git branch -D, git push --force

**Exit codes:** 0 = allow, 2 = block

### hook-post-write.sh

**Purpose:** PostToolUse hook — advisory note when test files are modified.

**Exit codes:** Always 0 (advisory only)
