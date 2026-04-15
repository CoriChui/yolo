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
output=$("$RUN_TESTS_SH" "$FEATURE1" --repo "$WORKDIR1" 2>&1)
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
output=$("$RUN_TESTS_SH" "$FEATURE2" --repo "$WORKDIR2" 2>&1)
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
output=$("$RUN_TESTS_SH" "$FEATURE3" --repo "$WORKDIR3" 2>&1)
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
output=$("$RUN_TESTS_SH" "$FEATURE4" --repo "$WORKDIR4" 2>&1)
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

# ── Test 5: --tail truncation ────────────────────────────────────────
echo "=== --tail truncation ==="

FEATURE5="$TMPDIR_TEST/feature5.yaml"
WORKDIR5="$TMPDIR_TEST/work5"
mkdir -p "$WORKDIR5"

cat > "$FEATURE5" <<'YAMLEOF'
---
slug: tail-test
title: Tail truncation test
test_commands: ["seq 1 300"]
lint_commands: []
---
## Plan
1. [ ] Do something
YAMLEOF

set +e
output=$("$RUN_TESTS_SH" "$FEATURE5" --repo "$WORKDIR5" 2>&1)
rc=$?
set -e

assert_exit_code "tail truncation exits 0" "0" "$rc"
assert_contains "output shows truncation message" "truncated" "$output"

# ── Test 6: Missing command fields (no lint/test commands at all) ────
echo "=== missing command fields ==="

FEATURE6="$TMPDIR_TEST/feature6.yaml"
WORKDIR6="$TMPDIR_TEST/work6"
mkdir -p "$WORKDIR6"

cat > "$FEATURE6" <<'YAMLEOF'
---
slug: no-commands
title: No commands feature
---
## Plan
1. [ ] Do something
YAMLEOF

set +e
output=$("$RUN_TESTS_SH" "$FEATURE6" --repo "$WORKDIR6" 2>&1)
rc=$?
set -e

assert_exit_code "missing command fields exits 0" "0" "$rc"

# ── Test 7: --repo alias works like --repo ────────────────────────
echo "=== --repo alias ==="

FEATURE7="$TMPDIR_TEST/feature7.yaml"
WORKDIR7="$TMPDIR_TEST/work7"
mkdir -p "$WORKDIR7"

cat > "$FEATURE7" <<'YAMLEOF'
---
slug: repo-alias
title: Repo alias test
test_commands: ["echo repo-alias-works"]
lint_commands: []
---
## Plan
1. [ ] Do something
YAMLEOF

set +e
output=$("$RUN_TESTS_SH" "$FEATURE7" --repo "$WORKDIR7" 2>&1)
rc=$?
set -e

assert_exit_code "--repo alias exits 0" "0" "$rc"
assert_contains "--repo alias runs commands" "repo-alias-works" "$output"

# ── Test 8: --tail custom value ──────────────────────────────────────
echo "=== --tail custom value ==="

FEATURE8="$TMPDIR_TEST/feature8.yaml"
WORKDIR8="$TMPDIR_TEST/work8"
mkdir -p "$WORKDIR8"

cat > "$FEATURE8" <<'YAMLEOF'
---
slug: tail-custom
title: Tail custom value test
test_commands: ["seq 1 20"]
lint_commands: []
---
## Plan
1. [ ] Do something
YAMLEOF

set +e
output=$("$RUN_TESTS_SH" "$FEATURE8" --repo "$WORKDIR8" --tail 5 2>&1)
rc=$?
set -e

assert_exit_code "tail custom value exits 0" "0" "$rc"
assert_contains "output is truncated" "truncated" "$output"
assert_contains "output shows last lines" "20" "$output"

# ── Test 9: --tail non-numeric rejected ─────────────────────────────
echo "=== --tail non-numeric rejected ==="

set +e
output=$("$RUN_TESTS_SH" "$FEATURE8" --repo "$WORKDIR8" --tail abc 2>&1)
rc=$?
set -e

assert_exit_code "--tail non-numeric rejected" "1" "$rc"
assert_contains "mentions positive integer" "positive integer" "$output"

# ── Test: Both lint and test commands fail ──────────────────────────────
echo "=== both lint and test commands fail ==="

FEATURE_BOTH_FAIL="$TMPDIR_TEST/feature_both_fail.yaml"
WORKDIR_BOTH_FAIL="$TMPDIR_TEST/work_both_fail"
mkdir -p "$WORKDIR_BOTH_FAIL"

cat > "$FEATURE_BOTH_FAIL" <<'YAMLEOF'
---
slug: both-fail
title: Both commands fail
test_commands: ["exit 1"]
lint_commands: ["exit 2"]
---
## Plan
1. [ ] Do something
YAMLEOF

set +e
output=$("$RUN_TESTS_SH" "$FEATURE_BOTH_FAIL" --repo "$WORKDIR_BOTH_FAIL" 2>&1)
rc=$?
set -e

assert_exit_code "both failing exits 1" "1" "$rc"
assert_contains "lint failure shown" "=== Exit code: 2 ===" "$output"
assert_contains "test failure shown" "=== Exit code: 1 ===" "$output"

# ── Error path tests ───────────────────────────────────────────────────

# Create a minimal feature file for error path tests
ERR_DIR="$TMPDIR_TEST/err-tests"
mkdir -p "$ERR_DIR"
ERR_FEATURE="$ERR_DIR/err-test.md"
cat > "$ERR_FEATURE" <<'FEAT'
---
goal: "error path testing"
lint_commands: []
test_commands: []
---
FEAT

# ── Test 10: No arguments → exit 1 with "No feature file specified" ──
echo "=== no arguments ==="

set +e
output=$("$RUN_TESTS_SH" 2>&1)
rc=$?
set -e

assert_exit_code "no arguments exits 1" "1" "$rc"
assert_contains "no arguments mentions missing file" "No feature file specified" "$output"

# ── Test 11: Flag as first arg → exit 1 with "first argument must be a feature file path" ──
echo "=== flag as first argument ==="

set +e
output=$("$RUN_TESTS_SH" --repo /tmp 2>&1)
rc=$?
set -e

assert_exit_code "flag as first arg exits 1" "1" "$rc"
assert_contains "flag as first arg mentions feature file path" "first argument must be a feature file path" "$output"

# ── Test 12: Nonexistent file → exit 1 with "Feature file not found" ──
echo "=== nonexistent feature file ==="

set +e
output=$("$RUN_TESTS_SH" "$ERR_DIR/no-such-file.md" 2>&1)
rc=$?
set -e

assert_exit_code "nonexistent file exits 1" "1" "$rc"
assert_contains "nonexistent file mentions not found" "Feature file not found" "$output"

# ── Test 13: --repo missing value → exit 1 with "requires a path argument" ──
echo "=== --repo missing value ==="

set +e
output=$("$RUN_TESTS_SH" "$ERR_FEATURE" --repo 2>&1)
rc=$?
set -e

assert_exit_code "--repo missing value exits 1" "1" "$rc"
assert_contains "--repo missing value mentions path argument" "requires a path argument" "$output"

# ── Test 14: Unknown argument → exit 1 with "Unknown argument" ──
echo "=== unknown argument ==="

set +e
output=$("$RUN_TESTS_SH" "$ERR_FEATURE" --bad-flag 2>&1)
rc=$?
set -e

assert_exit_code "unknown argument exits 1" "1" "$rc"
assert_contains "unknown argument mentioned" "Unknown argument" "$output"

# ── Test 15: --tail missing value → exit 1 with "requires a number argument" ──
echo "=== --tail missing value ==="

set +e
output=$("$RUN_TESTS_SH" "$ERR_FEATURE" --tail 2>&1)
rc=$?
set -e

assert_exit_code "--tail missing value exits 1" "1" "$rc"
assert_contains "--tail missing value mentions number argument" "requires a number argument" "$output"

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
  exit 1
fi
