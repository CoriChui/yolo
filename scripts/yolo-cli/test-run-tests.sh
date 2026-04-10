#!/usr/bin/env bash
# test-run-tests.sh — tests for scripts/yolo-cli/run-tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_TESTS_SH="$SCRIPT_DIR/run-tests.sh"

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

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    echo "    expected to contain: '$needle'"
    echo "    actual:              '$haystack'"
    FAIL=$(( FAIL + 1 ))
  fi
}

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

# ── Temp workspace ──────────────────────────────────────────────────
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── Test 1: Runs test_commands and lint_commands, output contains both ──
echo "=== runs test and lint commands ==="

FEATURE1="$TMPDIR_TEST/feature1.yaml"
WORKDIR1="$TMPDIR_TEST/work1"
mkdir -p "$WORKDIR1"

cat > "$FEATURE1" <<'YAMLEOF'
---
slug: my-feature
title: My feature
test_commands: ["echo test-output-here"]
lint_commands: ["echo lint-output-here"]
---
## Plan
1. [ ] Do something
YAMLEOF

set +e
output=$("$RUN_TESTS_SH" "$FEATURE1" --workdir "$WORKDIR1" 2>&1)
rc=$?
set -e

assert_exit_code "both pass exits 0" "0" "$rc"
assert_contains "output contains lint label" "=== LINT: echo lint-output-here ===" "$output"
assert_contains "output contains lint output" "lint-output-here" "$output"
assert_contains "output contains test label" "=== TEST: echo test-output-here ===" "$output"
assert_contains "output contains test output" "test-output-here" "$output"

# ── Test 2: Captures exit code on failure ─────────────────────────────
echo "=== captures exit code on failure ==="

FEATURE2="$TMPDIR_TEST/feature2.yaml"
WORKDIR2="$TMPDIR_TEST/work2"
mkdir -p "$WORKDIR2"

cat > "$FEATURE2" <<'YAMLEOF'
---
slug: failing
title: Failing feature
test_commands: ["exit 1"]
lint_commands: ["echo lint-ok"]
---
## Plan
1. [ ] Do something
YAMLEOF

set +e
output=$("$RUN_TESTS_SH" "$FEATURE2" --workdir "$WORKDIR2" 2>&1)
rc=$?
set -e

assert_exit_code "failing test command exits 1 overall" "1" "$rc"
assert_contains "exit code shown for failure" "=== Exit code: 1 ===" "$output"

# ── Test 3: Empty arrays are OK ──────────────────────────────────────
echo "=== empty arrays are OK ==="

FEATURE3="$TMPDIR_TEST/feature3.yaml"
WORKDIR3="$TMPDIR_TEST/work3"
mkdir -p "$WORKDIR3"

cat > "$FEATURE3" <<'YAMLEOF'
---
slug: empty
title: Empty commands
test_commands: []
lint_commands: []
---
## Plan
1. [ ] Do something
YAMLEOF

set +e
output=$("$RUN_TESTS_SH" "$FEATURE3" --workdir "$WORKDIR3" 2>&1)
rc=$?
set -e

assert_exit_code "empty arrays exit 0" "0" "$rc"

# ── Test 4: Multiple commands in array all execute ────────────────────
echo "=== multiple commands all execute ==="

FEATURE4="$TMPDIR_TEST/feature4.yaml"
WORKDIR4="$TMPDIR_TEST/work4"
mkdir -p "$WORKDIR4"

cat > "$FEATURE4" <<'YAMLEOF'
---
slug: multi
title: Multiple commands
test_commands: ["echo test-alpha", "echo test-beta"]
lint_commands: ["echo lint-one", "echo lint-two"]
---
## Plan
1. [ ] Do something
YAMLEOF

set +e
output=$("$RUN_TESTS_SH" "$FEATURE4" --workdir "$WORKDIR4" 2>&1)
rc=$?
set -e

assert_exit_code "multiple commands exit 0" "0" "$rc"
assert_contains "lint-one output" "lint-one" "$output"
assert_contains "lint-two output" "lint-two" "$output"
assert_contains "test-alpha output" "test-alpha" "$output"
assert_contains "test-beta output" "test-beta" "$output"
assert_contains "lint-one label" "=== LINT: echo lint-one ===" "$output"
assert_contains "lint-two label" "=== LINT: echo lint-two ===" "$output"
assert_contains "test-alpha label" "=== TEST: echo test-alpha ===" "$output"
assert_contains "test-beta label" "=== TEST: echo test-beta ===" "$output"

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
  exit 1
fi
