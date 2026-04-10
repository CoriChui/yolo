#!/usr/bin/env bash
# test-lib.sh — tests for scripts/yolo-cli/lib.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_dir_exists() {
  local label="$1" dir="$2"
  if [[ -d "$dir" ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label — directory '$dir' does not exist"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ── Temp workspace ──────────────────────────────────────────────────
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── slugify ─────────────────────────────────────────────────────────
echo "=== slugify ==="

assert_eq "basic phrase" \
  "add-dark-mode-support" \
  "$(slugify "Add dark mode support")"

assert_eq "long string truncated at 50 chars, no trailing hyphen" \
  "fix-the-null-pointer-in-auth-ts-line-45-and-also" \
  "$(slugify "Fix the null pointer in auth.ts line 45 and also make sure it handles edge cases")"

assert_eq "special characters stripped" \
  "hello-world-123" \
  "$(slugify "  Hello, World!!! 123  ")"

assert_eq "collapses multiple hyphens" \
  "foo-bar" \
  "$(slugify "foo---bar")"

assert_eq "leading/trailing hyphens trimmed" \
  "inner" \
  "$(slugify "---inner---")"

assert_eq "empty input" \
  "" \
  "$(slugify "")"

assert_eq "all special chars" \
  "" \
  "$(slugify "!@#\$%^&*()")"

# ── parse_frontmatter ──────────────────────────────────────────────
echo "=== parse_frontmatter ==="

FEATURE_FILE="$TMPDIR_TEST/feature.yaml"
cat > "$FEATURE_FILE" <<'YAMLEOF'
---
slug: dark-mode
title: Add dark mode support
branch: feature/dark-mode
status: in-progress
test_commands: ["pnpm test"]
---
## Criteria
- Must support system preference detection

## Plan
1. [x] Create theme provider — a1b2c3d
2. [ ] Add toggle component (test: none — trivial)
3. [ ] Persist preference (test: pnpm test -- theme)
YAMLEOF

assert_eq "extract branch" \
  "feature/dark-mode" \
  "$(parse_frontmatter "$FEATURE_FILE" "branch")"

assert_eq "extract test_commands" \
  '["pnpm test"]' \
  "$(parse_frontmatter "$FEATURE_FILE" "test_commands")"

assert_eq "extract slug" \
  "dark-mode" \
  "$(parse_frontmatter "$FEATURE_FILE" "slug")"

assert_eq "extract status" \
  "in-progress" \
  "$(parse_frontmatter "$FEATURE_FILE" "status")"

assert_eq "missing field returns empty" \
  "" \
  "$(parse_frontmatter "$FEATURE_FILE" "nonexistent")"

# ── parse_plan_tasks ────────────────────────────────────────────────
echo "=== parse_plan_tasks ==="

assert_eq "3-item plan" \
  "1 2 3" \
  "$(parse_plan_tasks "$FEATURE_FILE")"

# File with no plan section
NO_PLAN_FILE="$TMPDIR_TEST/no-plan.yaml"
cat > "$NO_PLAN_FILE" <<'YAMLEOF'
---
slug: test
---
## Criteria
- Something
YAMLEOF

assert_eq "no plan section returns empty" \
  "" \
  "$(parse_plan_tasks "$NO_PLAN_FILE")"

# File with more tasks
BIG_PLAN_FILE="$TMPDIR_TEST/big-plan.yaml"
cat > "$BIG_PLAN_FILE" <<'YAMLEOF'
---
slug: big
---
## Plan
1. [x] First task — abc1234
2. [x] Second task — def5678
3. [ ] Third task (test: pnpm test)
4. [ ] Fourth task (test: none — trivial)
5. [x] Fifth task — 1234567

## Verification
- Run all tests
YAMLEOF

assert_eq "5-item plan" \
  "1 2 3 4 5" \
  "$(parse_plan_tasks "$BIG_PLAN_FILE")"

# ── count_plan_tasks ────────────────────────────────────────────────
echo "=== count_plan_tasks ==="

assert_eq "count 3 tasks" \
  "3" \
  "$(count_plan_tasks "$FEATURE_FILE")"

assert_eq "count 5 tasks" \
  "5" \
  "$(count_plan_tasks "$BIG_PLAN_FILE")"

assert_eq "count 0 tasks (no plan)" \
  "0" \
  "$(count_plan_tasks "$NO_PLAN_FILE")"

# ── get_checked_tasks ───────────────────────────────────────────────
echo "=== get_checked_tasks ==="

assert_eq "only checked from feature file" \
  "1" \
  "$(get_checked_tasks "$FEATURE_FILE")"

assert_eq "checked from big plan" \
  "1 2 5" \
  "$(get_checked_tasks "$BIG_PLAN_FILE")"

assert_eq "no checked in empty plan" \
  "" \
  "$(get_checked_tasks "$NO_PLAN_FILE")"

# All checked
ALL_CHECKED_FILE="$TMPDIR_TEST/all-checked.yaml"
cat > "$ALL_CHECKED_FILE" <<'YAMLEOF'
---
slug: done
---
## Plan
1. [x] Done one — aaa1111
2. [x] Done two — bbb2222
YAMLEOF

assert_eq "all checked" \
  "1 2" \
  "$(get_checked_tasks "$ALL_CHECKED_FILE")"

# ── ensure_planning_dir ────────────────────────────────────────────
echo "=== ensure_planning_dir ==="

PLAN_ROOT="$TMPDIR_TEST/project"
ensure_planning_dir "$PLAN_ROOT"

assert_dir_exists "features/done exists" "$PLAN_ROOT/.planning/features/done"
assert_dir_exists "decisions exists"     "$PLAN_ROOT/.planning/decisions"
assert_dir_exists "debug-sessions exists" "$PLAN_ROOT/.planning/debug-sessions"

# Idempotent — calling again should not error
ensure_planning_dir "$PLAN_ROOT"
assert_dir_exists "idempotent call" "$PLAN_ROOT/.planning/features/done"

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
  exit 1
fi
