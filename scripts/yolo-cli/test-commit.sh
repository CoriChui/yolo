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
assert_exit_code "test deletion exits 0 (warning)" "0" "$rc"
assert_contains "warning mentions test count" "WARNING" "$output"

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
assert_exit_code "skip marker exits 0 (warning)" "0" "$rc"
assert_contains "warning mentions skip" "WARNING" "$output"

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

# ── Test: squash commit type ─────────────────────────────────────────
echo "=== squash commit type ==="

REPO_SQ="$(make_test_repo)"
TEMP_DIRS+=("$REPO_SQ")

echo "squash content" > "$REPO_SQ/squash.js"
git -C "$REPO_SQ" add squash.js

output=$("$COMMIT_SH" squash "Feature X (squash)" --repo "$REPO_SQ" 2>&1)
rc=$?
assert_exit_code "squash commit exits 0" "0" "$rc"

msg=$(git -C "$REPO_SQ" log -1 --pretty=format:%s)
assert_eq "squash commit message has prefix" "[squash] Feature X (squash)" "$msg"

# squash without message should fail
set +e
output=$("$COMMIT_SH" squash --repo "$REPO_SQ" 2>&1)
rc=$?
set -e
assert_exit_code "squash without message rejected" "1" "$rc"

# ── Test: --stage flag auto-stages files ─────────────────────────────
echo "=== --stage flag ==="

REPO_STAGE="$(make_test_repo)"
TEMP_DIRS+=("$REPO_STAGE")

echo "unstaged content" > "$REPO_STAGE/unstaged.js"
# Do NOT git add — let --stage handle it

output=$("$COMMIT_SH" wip "stage test" --repo "$REPO_STAGE" --stage 2>&1)
rc=$?
assert_exit_code "--stage auto-stages and commits" "0" "$rc"

msg=$(git -C "$REPO_STAGE" log -1 --pretty=format:%s)
assert_eq "--stage commit message" "[wip] stage test" "$msg"

# ── Test: non-numeric task number rejected ────────────────────────────
echo "=== non-numeric task number rejected ==="

REPO_NAN="$(make_test_repo)"
TEMP_DIRS+=("$REPO_NAN")

echo "x" > "$REPO_NAN/x.js"
git -C "$REPO_NAN" add x.js

set +e
output=$("$COMMIT_SH" task abc "msg" --repo "$REPO_NAN" 2>&1)
rc=$?
set -e
assert_exit_code "non-numeric task number rejected" "1" "$rc"
assert_contains "error mentions positive integer" "positive integer" "$output"

# ── Test: revert without message uses default ─────────────────────────
echo "=== revert without message uses default ==="

REPO_REVDEF="$(make_test_repo)"
TEMP_DIRS+=("$REPO_REVDEF")

echo "change" > "$REPO_REVDEF/change.js"
git -C "$REPO_REVDEF" add change.js

output=$("$COMMIT_SH" revert --repo "$REPO_REVDEF" 2>&1)
rc=$?
assert_exit_code "revert without message exits 0" "0" "$rc"

msg=$(git -C "$REPO_REVDEF" log -1 --pretty=format:%s)
assert_eq "revert default message" "[revert] revert" "$msg"

# ── Test: __tests__/ directory pattern detected ──────────────────────
echo "=== __tests__/ pattern detected ==="

REPO_JEST="$(make_test_repo)"
TEMP_DIRS+=("$REPO_JEST")

# Create a __tests__/ test file with 3 tests
mkdir -p "$REPO_JEST/__tests__"
cat > "$REPO_JEST/__tests__/auth.js" <<'EOF'
describe("auth", () => {
  test("login", () => { expect(true).toBe(true); });
  test("logout", () => { expect(true).toBe(true); });
  test("refresh", () => { expect(true).toBe(true); });
});
EOF
git -C "$REPO_JEST" add "__tests__/auth.js"
git -C "$REPO_JEST" commit -q -m "add jest tests"

# Reduce to 2 tests
cat > "$REPO_JEST/__tests__/auth.js" <<'EOF'
describe("auth", () => {
  test("login", () => { expect(true).toBe(true); });
  test("logout", () => { expect(true).toBe(true); });
});
EOF
git -C "$REPO_JEST" add "__tests__/auth.js"

set +e
output=$("$COMMIT_SH" task 1 "update auth" --repo "$REPO_JEST" 2>&1)
rc=$?
set -e
assert_exit_code "__tests__/ test reduction exits 0 (warning)" "0" "$rc"
assert_contains "__tests__/ detected test count warning" "WARNING" "$output"

# ── Test: --repo without value rejected ──────────────────────────────
echo "=== --repo missing value rejected ==="

REPO_NOREPO="$(make_test_repo)"
TEMP_DIRS+=("$REPO_NOREPO")

echo "x" > "$REPO_NOREPO/x.js"
git -C "$REPO_NOREPO" add x.js

set +e
output=$("$COMMIT_SH" task 1 "msg" --repo 2>&1)
rc=$?
set -e
assert_exit_code "--repo missing value rejected" "1" "$rc"
assert_contains "error mentions --repo requires path" "requires a path" "$output"

# ── Test: no arguments rejected ─────────────────────────────────────────
echo "=== no arguments rejected ==="

set +e
output=$("$COMMIT_SH" 2>&1)
rc=$?
set -e
assert_exit_code "no args exits 1" "1" "$rc"
assert_contains "no args shows usage" "No prefix type specified. Use: task, fix, wip, revert, squash" "$output"

# ── Test: deleted test file produces warning ─────────────────────────
echo "=== deleted test file produces warning ==="

REPO_DEL="$(make_test_repo)"
TEMP_DIRS+=("$REPO_DEL")

cat > "$REPO_DEL/auth.test.js" <<'EOF'
describe("auth", () => {
  test("login", () => { expect(true).toBe(true); });
  test("logout", () => { expect(true).toBe(true); });
});
EOF
git -C "$REPO_DEL" add auth.test.js
git -C "$REPO_DEL" commit -q -m "add auth tests"

git -C "$REPO_DEL" rm -q auth.test.js
echo "new code" > "$REPO_DEL/app.js"
git -C "$REPO_DEL" add app.js

output=$("$COMMIT_SH" task 1 "refactor auth" --repo "$REPO_DEL" 2>&1)
rc=$?
assert_exit_code "deleted test file exits 0 (warning)" "0" "$rc"
assert_contains "warning mentions deleted test" "test_file_deleted" "$output"

msg=$(git -C "$REPO_DEL" log -1 --pretty=format:%s)
assert_eq "commit proceeded despite deleted test" "[task-1] refactor auth" "$msg"

# ── Test: deleted test file suppressed by --allow-test-reduction ─────
echo "=== deleted test file suppressed by --allow-test-reduction ==="

REPO_DEL2="$(make_test_repo)"
TEMP_DIRS+=("$REPO_DEL2")

cat > "$REPO_DEL2/old.test.js" <<'EOF'
describe("old", () => { test("thing", () => {}); });
EOF
git -C "$REPO_DEL2" add old.test.js
git -C "$REPO_DEL2" commit -q -m "add old tests"

git -C "$REPO_DEL2" rm -q old.test.js
echo "replacement" > "$REPO_DEL2/new.js"
git -C "$REPO_DEL2" add new.js

output=$("$COMMIT_SH" task 1 "replace old" --repo "$REPO_DEL2" --allow-test-reduction 2>&1)
rc=$?
assert_exit_code "deleted test file suppressed" "0" "$rc"

msg=$(git -C "$REPO_DEL2" log -1 --pretty=format:%s)
assert_eq "commit succeeded with --allow-test-reduction" "[task-1] replace old" "$msg"

# ── Test: non-test file deletion is fine ──────────────────────────────
echo "=== non-test file deletion is fine ==="

REPO_DEL3="$(make_test_repo)"
TEMP_DIRS+=("$REPO_DEL3")

echo "old code" > "$REPO_DEL3/old-utils.js"
git -C "$REPO_DEL3" add old-utils.js
git -C "$REPO_DEL3" commit -q -m "add old utils"

git -C "$REPO_DEL3" rm -q old-utils.js
echo "new code" > "$REPO_DEL3/new-utils.js"
git -C "$REPO_DEL3" add new-utils.js

output=$("$COMMIT_SH" task 1 "replace utils" --repo "$REPO_DEL3" 2>&1)
rc=$?
assert_exit_code "non-test deletion passes cleanly" "0" "$rc"

# ── Test: --json outputs structured JSON ─────────────────────────────
echo "=== --json outputs structured JSON ==="

REPO_JSON="$(make_test_repo)"
TEMP_DIRS+=("$REPO_JSON")

cat > "$REPO_JSON/math.test.js" <<'EOF'
describe("math", () => {
  test("adds", () => { expect(1+1).toBe(2); });
  test("subtracts", () => { expect(2-1).toBe(1); });
});
EOF
git -C "$REPO_JSON" add math.test.js
git -C "$REPO_JSON" commit -q -m "add tests"

cat > "$REPO_JSON/math.test.js" <<'EOF'
describe("math", () => {
  test("adds", () => { expect(1+1).toBe(2); });
});
EOF
git -C "$REPO_JSON" add math.test.js

output=$("$COMMIT_SH" task 1 "simplify" --repo "$REPO_JSON" --json 2>/dev/null)
rc=$?
assert_exit_code "--json exits 0" "0" "$rc"
assert_contains "json has committed true" '"committed":true' "$output"
assert_contains "json has warnings array" '"warnings":' "$output"
assert_contains "json has test_count_decreased" '"test_count_decreased"' "$output"

# ── Test: --json with no issues produces clean output ────────────────
echo "=== --json with no issues ==="

REPO_JSON2="$(make_test_repo)"
TEMP_DIRS+=("$REPO_JSON2")

echo "code" > "$REPO_JSON2/app.js"
git -C "$REPO_JSON2" add app.js

output=$("$COMMIT_SH" task 1 "add feature" --repo "$REPO_JSON2" --json 2>/dev/null)
rc=$?
assert_exit_code "--json clean exits 0" "0" "$rc"
assert_contains "json has empty warnings" '"warnings":[]' "$output"
assert_contains "json has empty errors" '"errors":[]' "$output"

# ── YOLO trailers ─────────────────────────────────────────────────────
echo "=== YOLO trailers (feature + phase) ==="

# task commit on feature/<slug> branch emits both trailers
REPO_TR1="$(make_test_repo)"
TEMP_DIRS+=("$REPO_TR1")
git -C "$REPO_TR1" checkout -q -b feature/dark-mode
echo "code" > "$REPO_TR1/a.js"
git -C "$REPO_TR1" add a.js
"$COMMIT_SH" task 1 "first task" --repo "$REPO_TR1" >/dev/null 2>&1
body=$(git -C "$REPO_TR1" log -1 --pretty=format:%B)
assert_contains "task on feature branch: YOLO-Feature trailer present" "YOLO-Feature: dark-mode" "$body"
assert_contains "task on feature branch: YOLO-Phase trailer = do" "YOLO-Phase: do" "$body"

# fix commit on feature branch also emits do phase
echo "patch" > "$REPO_TR1/b.js"
git -C "$REPO_TR1" add b.js
"$COMMIT_SH" fix 1 "a fix" --repo "$REPO_TR1" >/dev/null 2>&1
body=$(git -C "$REPO_TR1" log -1 --pretty=format:%B)
assert_contains "fix on feature branch: YOLO-Phase = do" "YOLO-Phase: do" "$body"
assert_contains "fix on feature branch: feature trailer present" "YOLO-Feature: dark-mode" "$body"

# wip commit emits wip phase
echo "wip" > "$REPO_TR1/c.js"
git -C "$REPO_TR1" add c.js
"$COMMIT_SH" wip "parking" --repo "$REPO_TR1" >/dev/null 2>&1
body=$(git -C "$REPO_TR1" log -1 --pretty=format:%B)
assert_contains "wip: YOLO-Phase = wip" "YOLO-Phase: wip" "$body"

# revert commit emits revert phase
echo "r" > "$REPO_TR1/d.js"
git -C "$REPO_TR1" add d.js
"$COMMIT_SH" revert "undo" --repo "$REPO_TR1" >/dev/null 2>&1
body=$(git -C "$REPO_TR1" log -1 --pretty=format:%B)
assert_contains "revert: YOLO-Phase = revert" "YOLO-Phase: revert" "$body"

# Commit on main (no feature) does NOT emit YOLO-Feature trailer
REPO_TR2="$(make_test_repo)"
TEMP_DIRS+=("$REPO_TR2")
echo "code" > "$REPO_TR2/a.js"
git -C "$REPO_TR2" add a.js
"$COMMIT_SH" task 1 "no-slug task" --repo "$REPO_TR2" >/dev/null 2>&1
body=$(git -C "$REPO_TR2" log -1 --pretty=format:%B)
if [[ "$body" == *"YOLO-Feature:"* ]]; then
  assert_eq "task on main: no YOLO-Feature trailer" "pass" "fail"
else
  assert_eq "task on main: no YOLO-Feature trailer" "pass" "pass"
fi

# Squash commit on main emits ship phase (no slug trailer)
REPO_TR3="$(make_test_repo)"
TEMP_DIRS+=("$REPO_TR3")
echo "s" > "$REPO_TR3/s.js"
git -C "$REPO_TR3" add s.js
"$COMMIT_SH" squash "ship dark-mode" --repo "$REPO_TR3" >/dev/null 2>&1
body=$(git -C "$REPO_TR3" log -1 --pretty=format:%B)
assert_contains "squash on main: YOLO-Phase = ship" "YOLO-Phase: ship" "$body"

# Trailers are canonicalized: only one YOLO-Phase line even on re-emit
REPO_TR4="$(make_test_repo)"
TEMP_DIRS+=("$REPO_TR4")
git -C "$REPO_TR4" checkout -q -b feature/dedup-probe
echo "c" > "$REPO_TR4/c.js"
git -C "$REPO_TR4" add c.js
"$COMMIT_SH" task 1 "probe" --repo "$REPO_TR4" >/dev/null 2>&1
body=$(git -C "$REPO_TR4" log -1 --pretty=format:%B)
phase_count=$(printf '%s\n' "$body" | grep -c '^YOLO-Phase:')
assert_eq "single YOLO-Phase trailer (no dupes)" "1" "$phase_count"
feature_count=$(printf '%s\n' "$body" | grep -c '^YOLO-Feature:')
assert_eq "single YOLO-Feature trailer (no dupes)" "1" "$feature_count"

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
  exit 1
fi
