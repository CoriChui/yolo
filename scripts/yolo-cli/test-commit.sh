#!/usr/bin/env bash
# test-commit.sh — tests for scripts/yolo-cli/commit.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMIT_SH="$SCRIPT_DIR/commit.sh"

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

# ── Helpers ────────────────────────────────────────────────────────────
# Create a fresh temporary git repo with an initial commit.
make_test_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  # Initial commit so HEAD exists
  echo "init" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "init"
  printf '%s' "$dir"
}

# Track temp dirs for cleanup
TEMP_DIRS=()
cleanup() {
  for d in "${TEMP_DIRS[@]}"; do
    rm -rf "$d"
  done
}
trap cleanup EXIT

# ── Test: valid [task-N] commit ────────────────────────────────────────
echo "=== valid [task-N] commit ==="

REPO="$(make_test_repo)"
TEMP_DIRS+=("$REPO")

echo "some code" > "$REPO/app.js"
git -C "$REPO" add app.js

output=$("$COMMIT_SH" task 3 "implement auth module" --repo "$REPO" 2>&1)
rc=$?
assert_exit_code "task commit exits 0" "0" "$rc"

msg=$(git -C "$REPO" log -1 --pretty=format:%s)
assert_eq "task commit message has prefix" "[task-3] implement auth module" "$msg"

# ── Test: valid [fix-N] commit ─────────────────────────────────────────
echo "=== valid [fix-N] commit ==="

REPO2="$(make_test_repo)"
TEMP_DIRS+=("$REPO2")

echo "fix code" > "$REPO2/fix.js"
git -C "$REPO2" add fix.js

output=$("$COMMIT_SH" fix 7 "correct null pointer" --repo "$REPO2" 2>&1)
rc=$?
assert_exit_code "fix commit exits 0" "0" "$rc"

msg=$(git -C "$REPO2" log -1 --pretty=format:%s)
assert_eq "fix commit message has prefix" "[fix-7] correct null pointer" "$msg"

# ── Test: valid [wip] commit ──────────────────────────────────────────
echo "=== valid [wip] commit ==="

REPO3="$(make_test_repo)"
TEMP_DIRS+=("$REPO3")

echo "wip stuff" > "$REPO3/wip.js"
git -C "$REPO3" add wip.js

# wip with no message — should default
output=$("$COMMIT_SH" wip --repo "$REPO3" 2>&1)
rc=$?
assert_exit_code "wip commit exits 0" "0" "$rc"

msg=$(git -C "$REPO3" log -1 --pretty=format:%s)
assert_eq "wip commit default message" "[wip] Parking feature" "$msg"

# wip with custom message
echo "more wip" > "$REPO3/wip2.js"
git -C "$REPO3" add wip2.js

output=$("$COMMIT_SH" wip "halfway done" --repo "$REPO3" 2>&1)
rc=$?
assert_exit_code "wip commit with message exits 0" "0" "$rc"

msg=$(git -C "$REPO3" log -1 --pretty=format:%s)
assert_eq "wip commit custom message" "[wip] halfway done" "$msg"

# ── Test: valid [revert] commit ───────────────────────────────────────
echo "=== valid [revert] commit ==="

REPO4="$(make_test_repo)"
TEMP_DIRS+=("$REPO4")

echo "revert stuff" > "$REPO4/revert.js"
git -C "$REPO4" add revert.js

output=$("$COMMIT_SH" revert "undo bad deploy" --repo "$REPO4" 2>&1)
rc=$?
assert_exit_code "revert commit exits 0" "0" "$rc"

msg=$(git -C "$REPO4" log -1 --pretty=format:%s)
assert_eq "revert commit message" "[revert] undo bad deploy" "$msg"

# ── Test: invalid prefix type rejected ─────────────────────────────────
echo "=== invalid prefix type rejected ==="

REPO5="$(make_test_repo)"
TEMP_DIRS+=("$REPO5")

echo "x" > "$REPO5/x.js"
git -C "$REPO5" add x.js

output=$("$COMMIT_SH" yolo 1 "bad" --repo "$REPO5" 2>&1) || true
rc=$?
# The above `|| true` eats the exit code; re-run properly
set +e
output=$("$COMMIT_SH" yolo 1 "bad" --repo "$REPO5" 2>&1)
rc=$?
set -e
assert_exit_code "unknown prefix rejected" "1" "$rc"
assert_contains "error message mentions unknown" "Unknown" "$output"

# ── Test: test deletion detected and rejected ──────────────────────────
echo "=== test deletion detected and rejected ==="

REPO6="$(make_test_repo)"
TEMP_DIRS+=("$REPO6")

# Create a test file with 3 tests and commit it
cat > "$REPO6/math.test.js" <<'EOF'
describe("math", () => {
  test("adds", () => { expect(1+1).toBe(2); });
  test("subtracts", () => { expect(2-1).toBe(1); });
  test("multiplies", () => { expect(2*3).toBe(6); });
});
EOF
git -C "$REPO6" add math.test.js
git -C "$REPO6" commit -q -m "add tests"

# Now reduce to 2 tests (delete one)
cat > "$REPO6/math.test.js" <<'EOF'
describe("math", () => {
  test("adds", () => { expect(1+1).toBe(2); });
  test("subtracts", () => { expect(2-1).toBe(1); });
});
EOF
git -C "$REPO6" add math.test.js

set +e
output=$("$COMMIT_SH" task 1 "refactor math" --repo "$REPO6" 2>&1)
rc=$?
set -e
assert_exit_code "test deletion rejected" "1" "$rc"
assert_contains "error mentions test count" "Test count decreased" "$output"

# ── Test: skip marker detected and rejected ────────────────────────────
echo "=== skip marker detected and rejected ==="

REPO7="$(make_test_repo)"
TEMP_DIRS+=("$REPO7")

# Create a clean test file
cat > "$REPO7/auth.test.js" <<'EOF'
describe("auth", () => {
  test("login", () => { expect(true).toBe(true); });
  test("logout", () => { expect(true).toBe(true); });
});
EOF
git -C "$REPO7" add auth.test.js
git -C "$REPO7" commit -q -m "add auth tests"

# Add a .skip marker
cat > "$REPO7/auth.test.js" <<'EOF'
describe("auth", () => {
  test("login", () => { expect(true).toBe(true); });
  test.skip("logout", () => { expect(true).toBe(true); });
  test("new test", () => { expect(true).toBe(true); });
});
EOF
git -C "$REPO7" add auth.test.js

set +e
output=$("$COMMIT_SH" task 2 "update auth" --repo "$REPO7" 2>&1)
rc=$?
set -e
assert_exit_code "skip marker rejected" "1" "$rc"
assert_contains "error mentions skip" "skip" "$output"

# ── Test: --allow-test-reduction bypasses test checks ──────────────────
echo "=== --allow-test-reduction bypasses test checks ==="

REPO8="$(make_test_repo)"
TEMP_DIRS+=("$REPO8")

# Create a test file with 3 tests and commit it
cat > "$REPO8/math.test.js" <<'EOF'
describe("math", () => {
  test("adds", () => { expect(1+1).toBe(2); });
  test("subtracts", () => { expect(2-1).toBe(1); });
  test("multiplies", () => { expect(2*3).toBe(6); });
});
EOF
git -C "$REPO8" add math.test.js
git -C "$REPO8" commit -q -m "add tests"

# Reduce tests (would normally fail)
cat > "$REPO8/math.test.js" <<'EOF'
describe("math", () => {
  test("adds", () => { expect(1+1).toBe(2); });
});
EOF
git -C "$REPO8" add math.test.js

output=$("$COMMIT_SH" task 1 "simplify math" --repo "$REPO8" --allow-test-reduction 2>&1)
rc=$?
assert_exit_code "allow-test-reduction bypasses check" "0" "$rc"

msg=$(git -C "$REPO8" log -1 --pretty=format:%s)
assert_eq "commit still has correct prefix" "[task-1] simplify math" "$msg"

# ── Test: wip skips test integrity checks ──────────────────────────────
echo "=== wip skips test integrity checks ==="

REPO9="$(make_test_repo)"
TEMP_DIRS+=("$REPO9")

# Create a test file with tests and commit it
cat > "$REPO9/math.test.js" <<'EOF'
describe("math", () => {
  test("adds", () => { expect(1+1).toBe(2); });
  test("subtracts", () => { expect(2-1).toBe(1); });
});
EOF
git -C "$REPO9" add math.test.js
git -C "$REPO9" commit -q -m "add tests"

# Delete all tests (would normally fail for task/fix)
cat > "$REPO9/math.test.js" <<'EOF'
describe("math", () => {
});
EOF
git -C "$REPO9" add math.test.js

output=$("$COMMIT_SH" wip --repo "$REPO9" 2>&1)
rc=$?
assert_exit_code "wip skips test integrity" "0" "$rc"

# ── Test: task requires N and message ──────────────────────────────────
echo "=== task requires N and message ==="

REPO10="$(make_test_repo)"
TEMP_DIRS+=("$REPO10")

echo "x" > "$REPO10/x.js"
git -C "$REPO10" add x.js

# task without N
set +e
output=$("$COMMIT_SH" task --repo "$REPO10" 2>&1)
rc=$?
set -e
assert_exit_code "task without N rejected" "1" "$rc"

# task with N but no message
set +e
output=$("$COMMIT_SH" task 1 --repo "$REPO10" 2>&1)
rc=$?
set -e
assert_exit_code "task without message rejected" "1" "$rc"

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
  exit 1
fi
