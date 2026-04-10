#!/usr/bin/env bash
#
# test-reconcile-edge-cases.sh — Edge case tests for reconcile.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECONCILE="$SCRIPT_DIR/reconcile.sh"
TEST_DIR="/tmp/yolo-spike-edge"
PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo -e "  ${GREEN}PASS${NC}: $label"; PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label"
    echo "    Expected: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label"; PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
# Setup
# ============================================================
echo -e "${YELLOW}=== Setting up edge case test repo ===${NC}"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
git init -b main
git config user.email "test@test.com"
git config user.name "Test"
echo "init" > README.md
mkdir -p .planning/features
git add -A
git commit -m "Initial commit"

# ============================================================
# Edge 1: Multiple commits for the same task (should use latest)
# ============================================================
echo ""
echo -e "${YELLOW}=== Edge 1: Multiple commits for same task ===${NC}"

git checkout -b feature/multi-commit
echo "v1" > file1.txt
git add file1.txt
git commit -m "[task-1] First attempt at task 1"
HASH_OLD=$(git log -1 --format='%h')

echo "v2" > file1.txt
git add file1.txt
git commit -m "[task-1] Fix task 1 implementation"
HASH_NEW=$(git log -1 --format='%h')

cat > "$TEST_DIR/.planning/features/multi-commit.md" << 'EOF'
---
goal: Multi-commit test
branch: feature/multi-commit
---

## Plan
1. [ ] Do task 1
2. [ ] Do task 2
EOF

OUTPUT=$("$RECONCILE" "$TEST_DIR/.planning/features/multi-commit.md" "feature/multi-commit" --repo "$TEST_DIR" 2>&1)
echo "$OUTPUT"
echo ""

# The script uses latest commit (first in git log = most recent)
assert_contains "Uses latest commit for task-1" "$OUTPUT" "$HASH_NEW"

# ============================================================
# Edge 2: Task with "test: none" annotation in the label
# ============================================================
echo ""
echo -e "${YELLOW}=== Edge 2: Complex task labels with special characters ===${NC}"

git checkout main
git checkout -b feature/complex-labels

echo "x" > x.txt
git add x.txt
git commit -m "[task-1] Add localStorage persistence + SSR-safe init script"

cat > "$TEST_DIR/.planning/features/complex-labels.md" << 'EOF'
---
goal: Complex labels test
branch: feature/complex-labels
---

## Plan
1. [ ] Add localStorage persistence + SSR-safe init script (test: none — no unit test for script tag injection, verified by check step criterion "no flash")
2. [ ] Replace $variables and special chars: [brackets], (parens)
EOF

OUTPUT=$("$RECONCILE" "$TEST_DIR/.planning/features/complex-labels.md" "feature/complex-labels" --repo "$TEST_DIR" 2>&1)
echo "$OUTPUT"
echo ""

assert_contains "Handles complex label" "$OUTPUT" "task-1"
assert_contains "Detects commit for task-1" "$OUTPUT" "DRIFT: task-1 is UNCHECKED"

# ============================================================
# Edge 3: Feature file missing ## Plan section
# ============================================================
echo ""
echo -e "${YELLOW}=== Edge 3: Missing ## Plan section ===${NC}"

cat > "$TEST_DIR/.planning/features/no-plan.md" << 'EOF'
---
goal: No plan test
branch: feature/complex-labels
---

## Criteria
- [ ] Something

## Context
No plan here yet.
EOF

EXIT_CODE=0
OUTPUT=$("$RECONCILE" "$TEST_DIR/.planning/features/no-plan.md" "feature/complex-labels" --repo "$TEST_DIR" 2>&1) || EXIT_CODE=$?
echo "$OUTPUT"
assert_exit_code "Exits with error for missing plan" "1" "$EXIT_CODE"
assert_contains "Reports no tasks found" "$OUTPUT" "No tasks found"

# ============================================================
# Edge 4: Feature file with empty verification section
# ============================================================
echo ""
echo -e "${YELLOW}=== Edge 4: Empty verification vs populated ===${NC}"

git checkout main
git checkout -b feature/verify-test

echo "a" > a.txt
git add a.txt
git commit -m "[task-1] Only task"

# Empty verification (just the heading + placeholder comment)
cat > "$TEST_DIR/.planning/features/verify-empty.md" << 'EOF'
---
goal: Verify empty test
branch: feature/verify-test
---

## Plan
1. [x] Only task

## Verification
(Written by check step — evidence citations here)
EOF

OUTPUT=$("$RECONCILE" "$TEST_DIR/.planning/features/verify-empty.md" "feature/verify-test" --repo "$TEST_DIR" 2>&1)
echo "$OUTPUT"
echo ""
assert_contains "Empty verification -> check step" "$OUTPUT" "check (all 1 tasks done, needs verification)"

# Populated verification
cat > "$TEST_DIR/.planning/features/verify-full.md" << 'EOF'
---
goal: Verify full test
branch: feature/verify-test
---

## Plan
1. [x] Only task

## Verification
Tests passed: all 5 assertions green.
Linter: 0 errors, 0 warnings.
EOF

OUTPUT=$("$RECONCILE" "$TEST_DIR/.planning/features/verify-full.md" "feature/verify-test" --repo "$TEST_DIR" 2>&1)
echo "$OUTPUT"
echo ""
assert_contains "Populated verification -> ship step" "$OUTPUT" "ship (all tasks done, verified)"

# ============================================================
# Edge 5: Non-sequential task numbers (gaps)
# ============================================================
echo ""
echo -e "${YELLOW}=== Edge 5: Non-sequential task numbers ===${NC}"

git checkout main
git checkout -b feature/gaps

echo "x" > x.txt && git add x.txt && git commit -m "[task-1] First"
echo "y" > y.txt && git add y.txt && git commit -m "[task-3] Third (skipped 2)"
echo "z" > z.txt && git add z.txt && git commit -m "[task-5] Fifth (skipped 4)"

cat > "$TEST_DIR/.planning/features/gaps.md" << 'EOF'
---
goal: Gaps test
branch: feature/gaps
---

## Plan
1. [ ] First
3. [ ] Third
5. [ ] Fifth
EOF

OUTPUT=$("$RECONCILE" "$TEST_DIR/.planning/features/gaps.md" "feature/gaps" --repo "$TEST_DIR" 2>&1)
echo "$OUTPUT"
echo ""

assert_contains "Handles task-1" "$OUTPUT" "task-1"
assert_contains "Handles task-3" "$OUTPUT" "task-3"
assert_contains "Handles task-5" "$OUTPUT" "task-5"
assert_contains "All detected as drift" "$OUTPUT" "Total drift items: 3"

# ============================================================
# Edge 6: Timing with many commits (stress test)
# ============================================================
echo ""
echo -e "${YELLOW}=== Edge 6: Performance with 50 task commits ===${NC}"

git checkout main
git checkout -b feature/stress

PLAN_LINES=""
for i in $(seq 1 50); do
  echo "file $i" > "file${i}.txt"
  git add "file${i}.txt"
  git commit -m "[task-${i}] Implement task $i" --allow-empty
  PLAN_LINES="${PLAN_LINES}${i}. [ ] Implement task $i\n"
done

cat > "$TEST_DIR/.planning/features/stress.md" << EOF
---
goal: Stress test
branch: feature/stress
---

## Plan
$(echo -e "$PLAN_LINES")
EOF

OUTPUT=$("$RECONCILE" "$TEST_DIR/.planning/features/stress.md" "feature/stress" --repo "$TEST_DIR" 2>&1)
ELAPSED=$(echo "$OUTPUT" | grep "Elapsed:" | awk '{print $2}')
echo "  50 tasks reconciled in: $ELAPSED"

assert_contains "All 50 tasks found" "$OUTPUT" "check (all 50 tasks done, needs verification)"

# ============================================================
# Summary
# ============================================================
echo ""
echo "========================================"
echo -e "  Edge cases: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then exit 1; fi
echo -e "  ${GREEN}All edge case tests passed!${NC}"
