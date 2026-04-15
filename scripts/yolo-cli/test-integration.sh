#!/usr/bin/env bash
# test-integration.sh — end-to-end integration test for the do→check→ship flow.
#
# Exercises: lib.sh, commit.sh, reconcile.sh, run-tests.sh, validate-plan.sh
# all working together in a single simulated feature lifecycle.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMIT_SH="$SCRIPT_DIR/commit.sh"
RECONCILE_SH="$SCRIPT_DIR/reconcile.sh"
RUN_TESTS_SH="$SCRIPT_DIR/run-tests.sh"
VALIDATE_PLAN_SH="$SCRIPT_DIR/validate-plan.sh"
VERIFY_SH="$SCRIPT_DIR/verify-commit.sh"

PASS=0
FAIL=0

# ── Assertion helpers ─────────────────────────────────────────────────

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    echo "    expected exit code: $expected"
    echo "    actual exit code:   $actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    echo "    expected to contain: '$needle'"
    echo "    actual:              '${haystack:0:200}'"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_file_contains() {
  local label="$1" file="$2" needle="$3"
  if grep -qF "$needle" "$file"; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    echo "    expected file to contain: '$needle'"
    echo "    file: $file"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ── Setup: create temp git repo ──────────────────────────────────────

TEST_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

echo "=== Integration test: do→check flow ==="
echo "  Test repo: $TEST_DIR"
echo ""

# Initialize repo
git -C "$TEST_DIR" init -b main -q
git -C "$TEST_DIR" config user.email "test@test.com"
git -C "$TEST_DIR" config user.name "Test"

echo "# Test Project" > "$TEST_DIR/README.md"
git -C "$TEST_DIR" add README.md
git -C "$TEST_DIR" commit -q -m "Initial commit"

# Create .planning/features directory
mkdir -p "$TEST_DIR/.planning/features"

# Create the feature file
FEATURE_FILE="$TEST_DIR/.planning/features/test-feature.md"
cat > "$FEATURE_FILE" << 'FEATURE'
---
goal: Add greeting functions
branch: feature/test-feature
worktree: /tmp/not-used
created: 2026-04-10
test_commands: ["echo 'all tests passed'"]
lint_commands: ["echo 'no lint errors'"]
---

## Criteria
- [ ] Greeting function exists
- [ ] Tests pass

## Context
Integration test feature.

## Plan
1. [ ] Add greeting function to app.js with comprehensive unit test that verifies greeting returns the correct expected string for any given name input parameter
  - test: app.test.js — greet returns correct string
  - files: app.js, app.test.js
2. [ ] Add farewell function to app.js with comprehensive unit test that verifies farewell returns the correct expected goodbye string for any given name parameter
  - test: app.test.js — farewell returns correct string
  - files: app.js, app.test.js

## Verification
(Written by check step)
FEATURE

git -C "$TEST_DIR" add .planning
git -C "$TEST_DIR" commit -q -m "Add feature file"

# Create feature branch
git -C "$TEST_DIR" checkout -q -b feature/test-feature

# ── Step 1: DO — task-1 commit ───────────────────────────────────────

echo "=== Step 1: task-1 commit (commit.sh) ==="

cat > "$TEST_DIR/app.js" << 'EOF'
function greet(name) {
  return `Hello, ${name}!`;
}
module.exports = { greet };
EOF

cat > "$TEST_DIR/app.test.js" << 'EOF'
const { greet } = require('./app');
describe("greet", () => {
  test("returns greeting for name", () => {
    expect(greet("Alice")).toBe("Hello, Alice!");
  });
});
EOF

git -C "$TEST_DIR" add app.js app.test.js

set +e
output=$("$COMMIT_SH" task 1 "Add greeting function with unit test" --repo "$TEST_DIR" 2>&1)
rc_task1=$?
set -e

assert_exit_code "task-1 commit succeeds" "0" "$rc_task1"

# Verify task-1 commit
set +e
verify_output=$("$VERIFY_SH" task-1 "app.js,app.test.js" --repo "$TEST_DIR" 2>&1)
rc_verify1=$?
set -e

assert_exit_code "verify-commit task-1 succeeds" "0" "$rc_verify1"

# ── Step 2: DO — task-2 commit ───────────────────────────────────────

echo ""
echo "=== Step 2: task-2 commit (commit.sh) ==="

cat > "$TEST_DIR/app.js" << 'EOF'
function greet(name) {
  return `Hello, ${name}!`;
}
function farewell(name) {
  return `Goodbye, ${name}!`;
}
module.exports = { greet, farewell };
EOF

cat > "$TEST_DIR/app.test.js" << 'EOF'
const { greet, farewell } = require('./app');
describe("greet", () => {
  test("returns greeting for name", () => {
    expect(greet("Alice")).toBe("Hello, Alice!");
  });
});
describe("farewell", () => {
  test("returns goodbye for name", () => {
    expect(farewell("Bob")).toBe("Goodbye, Bob!");
  });
});
EOF

git -C "$TEST_DIR" add app.js app.test.js

set +e
output=$("$COMMIT_SH" task 2 "Add farewell function with unit test" --repo "$TEST_DIR" 2>&1)
rc_task2=$?
set -e

assert_exit_code "task-2 commit succeeds" "0" "$rc_task2"

# Verify task-2 commit
set +e
verify_output=$("$VERIFY_SH" task-2 "app.js,app.test.js" --repo "$TEST_DIR" 2>&1)
rc_verify2=$?
set -e

assert_exit_code "verify-commit task-2 succeeds" "0" "$rc_verify2"

# ── Step 3: Reconcile with --fix ─────────────────────────────────────

echo ""
echo "=== Step 3: reconcile --fix (reconcile.sh) ==="

set +e
reconcile_output=$("$RECONCILE_SH" "$FEATURE_FILE" "feature/test-feature" --fix --repo "$TEST_DIR" 2>&1)
rc_reconcile=$?
set -e

assert_exit_code "reconcile --fix succeeds" "0" "$rc_reconcile"

# ── Step 4: Verify checkboxes got checked ────────────────────────────

echo ""
echo "=== Step 4: verify checkboxes after reconcile ==="

assert_file_contains \
  "task-1 checkbox is checked after reconcile" \
  "$FEATURE_FILE" \
  "1. [x] Add greeting function"

assert_file_contains \
  "task-2 checkbox is checked after reconcile" \
  "$FEATURE_FILE" \
  "2. [x] Add farewell function"

# ── Step 5: run-tests exits 0 ───────────────────────────────────────

echo ""
echo "=== Step 5: run-tests (run-tests.sh) ==="

set +e
run_tests_output=$("$RUN_TESTS_SH" "$FEATURE_FILE" --repo "$TEST_DIR" 2>&1)
rc_run_tests=$?
set -e

assert_exit_code "run-tests exits 0" "0" "$rc_run_tests"

# ── Step 6: validate-plan passes ─────────────────────────────────────

echo ""
echo "=== Step 6: validate-plan (validate-plan.sh) ==="

set +e
validate_output=$("$VALIDATE_PLAN_SH" "$FEATURE_FILE" 2>&1)
rc_validate=$?
set -e

assert_exit_code "validate-plan exits 0" "0" "$rc_validate"

# ── Step 7: Step derivation reports "check" ──────────────────────────

echo ""
echo "=== Step 7: step derivation — reconcile reports 'check' ==="

# Run reconcile again (without --fix) to get the step derivation
set +e
step_output=$("$RECONCILE_SH" "$FEATURE_FILE" "feature/test-feature" --repo "$TEST_DIR" 2>&1)
rc_step=$?
set -e

assert_contains \
  "step derivation reports 'check' (all tasks done, needs verification)" \
  "check (all 2 tasks done, needs verification)" \
  "$step_output"

# ── Step 8: reconcile reports no drift after fix ─────────────────────

echo ""
echo "=== Step 8: no drift after fix ==="

assert_contains \
  "reconcile reports no drift after fix" \
  "No drift detected" \
  "$step_output"

# ── Step 9: Ship — squash merge to main ──────────────────────────────

echo ""
echo "=== Step 9: ship — squash merge to main ==="

# Switch to main and squash merge
git -C "$TEST_DIR" checkout -q main

set +e
git -C "$TEST_DIR" merge --squash feature/test-feature 2>&1
merge_rc=$?
set -e

assert_exit_code "squash merge succeeds" "0" "$merge_rc"

# Commit the squash using commit.sh
set +e
squash_output=$("$COMMIT_SH" squash "Add greeting functions" --repo "$TEST_DIR" --stage 2>&1)
rc_squash=$?
set -e

assert_exit_code "squash commit succeeds" "0" "$rc_squash"

# Verify the squash commit message has the [squash] prefix
set +e
last_msg=$(git -C "$TEST_DIR" log -1 --format='%s' 2>&1)
set -e

assert_contains "squash commit has [squash] prefix" "[squash]" "$last_msg"

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "========================================"

if (( FAIL > 0 )); then
  exit 1
fi
