#!/usr/bin/env bash
# test-validate-plan.sh — tests for scripts/yolo-cli/validate-plan.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SH="$SCRIPT_DIR/validate-plan.sh"

PASS=0
FAIL=0

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
    echo "    actual:              '$haystack'"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ── Temp workspace ────────────────────────────────────────────────────
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── Test 1: Valid 3-task plan passes (1 test:none is OK since <50%) ───
echo "=== valid 3-task plan passes ==="

VALID_FILE="$TMPDIR_TEST/valid-3.yaml"
cat > "$VALID_FILE" <<'EOF'
---
slug: valid-feature
title: A valid feature with three tasks
status: planned
---
## Criteria
- Must work correctly

## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions across the entire application (test: pnpm test -- auth)
2. [ ] Add the user profile page with avatar upload and comprehensive form validation for all required input fields across the entire user-facing interface (test: none — trivial UI)
3. [ ] Write integration tests for the complete login flow covering success failure timeout and all edge cases thoroughly across every relevant component (test: pnpm test -- integration)

## Verification
- Run all tests
EOF

set +e
output=$("$VALIDATE_SH" "$VALID_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "valid 3-task plan exits 0" "0" "$rc"

# ── Test 2: >50% test:none rejected ──────────────────────────────────
echo "=== >50% test:none rejected ==="

TESTNONE_FILE="$TMPDIR_TEST/too-many-testnone.yaml"
cat > "$TESTNONE_FILE" <<'EOF'
---
slug: testnone-feature
title: Feature with too many test none tasks
status: planned
---
## Criteria
- Something

## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions across the entire application (test: none — trivial)
2. [ ] Add the user profile page with avatar upload and comprehensive form validation for all required input fields across the entire user-facing interface (test: none — simple)
3. [ ] Write integration tests for the complete login flow covering success failure timeout and all edge cases thoroughly across every relevant component (test: pnpm test -- integration)
EOF

set +e
output=$("$VALIDATE_SH" "$TESTNONE_FILE" 2>&1)
rc=$?
set -e
assert_exit_code ">50% test:none rejected" "1" "$rc"
assert_contains "mentions untested count" "tasks without tests" "$output"

# ── Test 3: Short description rejected (<20 words) ───────────────────
echo "=== short description rejected ==="

SHORT_FILE="$TMPDIR_TEST/short-desc.yaml"
cat > "$SHORT_FILE" <<'EOF'
---
slug: short-desc
title: Feature with short description
status: planned
---
## Criteria
- Something

## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions across the entire application (test: pnpm test)
2. [ ] Fix bug (test: pnpm test)
3. [ ] Write integration tests for the complete login flow covering success failure timeout and all edge cases thoroughly across every relevant component (test: pnpm test)
EOF

set +e
output=$("$VALIDATE_SH" "$SHORT_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "short description rejected" "1" "$rc"
assert_contains "mentions word count" "words" "$output"

# ── Test 4: >12 tasks rejected ───────────────────────────────────────
echo "=== >12 tasks rejected ==="

BIG_FILE="$TMPDIR_TEST/too-many-tasks.yaml"
cat > "$BIG_FILE" <<'EOF'
---
slug: big-feature
title: Feature with too many tasks
status: planned
---
## Plan
1. [ ] Implement the first module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
2. [ ] Implement the second module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
3. [ ] Implement the third module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
4. [ ] Implement the fourth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
5. [ ] Implement the fifth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
6. [ ] Implement the sixth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
7. [ ] Implement the seventh module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
8. [ ] Implement the eighth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
9. [ ] Implement the ninth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
10. [ ] Implement the tenth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
11. [ ] Implement the eleventh module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
12. [ ] Implement the twelfth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
13. [ ] Implement the thirteenth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
EOF

set +e
output=$("$VALIDATE_SH" "$BIG_FILE" 2>&1)
rc=$?
set -e
assert_exit_code ">12 tasks rejected" "1" "$rc"
assert_contains "mentions split" "split" "$output"

# ── Test 5: Empty plan (no ## Plan section) rejected ─────────────────
echo "=== empty plan rejected ==="

EMPTY_FILE="$TMPDIR_TEST/no-plan.yaml"
cat > "$EMPTY_FILE" <<'EOF'
---
slug: empty-feature
title: Feature with no plan
status: planned
---
## Criteria
- Something
EOF

set +e
output=$("$VALIDATE_SH" "$EMPTY_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "empty plan rejected" "1" "$rc"
assert_contains "mentions plan section" "Plan" "$output"

# ── Test 6: Valid 12-task plan passes (boundary case) ─────────────────
echo "=== valid 12-task plan passes (boundary) ==="

BOUNDARY_FILE="$TMPDIR_TEST/boundary-12.yaml"
cat > "$BOUNDARY_FILE" <<'EOF'
---
slug: boundary-feature
title: Feature with exactly twelve tasks at the boundary limit
status: planned
---
## Plan
1. [ ] Implement the first module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
2. [ ] Implement the second module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
3. [ ] Implement the third module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
4. [ ] Implement the fourth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
5. [ ] Implement the fifth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: none — trivial)
6. [ ] Implement the sixth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
7. [ ] Implement the seventh module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
8. [ ] Implement the eighth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
9. [ ] Implement the ninth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: none — trivial)
10. [ ] Implement the tenth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
11. [ ] Implement the eleventh module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
12. [ ] Implement the twelfth module with proper error handling and token refresh logic and validation for all cases across every component and module (test: pnpm test)
EOF

set +e
output=$("$VALIDATE_SH" "$BOUNDARY_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "valid 12-task plan exits 0" "0" "$rc"

# ── Test 7: Directory path in files list rejected ────────────────────
echo "=== directory path in files rejected ==="

DIRPATH_FILE="$TMPDIR_TEST/dir-path.yaml"
cat > "$DIRPATH_FILE" <<'EOF'
---
slug: dir-path-feature
title: Feature with directory path in files
status: planned
---
## Plan
1. [ ] Implement the authentication module with proper error handling and robust refresh logic for all active user sessions on every platform — files: src/auth/, utils.ts (test: pnpm test)
2. [ ] Write integration tests for the complete login flow covering success failure timeout and all edge cases thoroughly across every relevant component (test: pnpm test)
EOF

set +e
output=$("$VALIDATE_SH" "$DIRPATH_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "directory path in files rejected" "1" "$rc"
assert_contains "mentions directory path" "directory path" "$output"

# ── Test 8: test:none without parentheses also detected ────────────
echo "=== test:none without parens detected ==="

NOPARENS_FILE="$TMPDIR_TEST/no-parens.yaml"
cat > "$NOPARENS_FILE" <<'EOF'
---
slug: no-parens-feature
title: Feature with test none without parentheses
status: planned
---
## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions across the entire application test: none trivial
2. [ ] Add the user profile page with avatar upload and comprehensive form validation for all required input fields across the entire user-facing interface test: none simple
3. [ ] Write integration tests for the complete login flow covering success failure timeout and all edge cases thoroughly across every relevant component (test: pnpm test -- integration)
EOF

set +e
output=$("$VALIDATE_SH" "$NOPARENS_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "test:none without parens also rejected" "1" "$rc"
assert_contains "mentions untested count (no parens)" "tasks without tests" "$output"

# ── Test 9: --no-test-suite skips test:none gate ──────────────────
echo "=== --no-test-suite skips test:none gate ==="

ALL_NONE_FILE="$TMPDIR_TEST/all-testnone.yaml"
cat > "$ALL_NONE_FILE" <<'EOF'
---
slug: no-suite-feature
title: Feature with no test suite available so all tasks are test none
status: planned
---
## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions across the entire application (test: none — no test suite)
2. [ ] Add the user profile page with avatar upload and comprehensive form validation for all required input fields across the entire user-facing interface (test: none — no test suite)
3. [ ] Write the configuration module with proper error handling and environment variable parsing for all deployment targets across every environment and region (test: none — no test suite)
EOF

set +e
output=$("$VALIDATE_SH" "$ALL_NONE_FILE" --no-test-suite 2>&1)
rc=$?
set -e
assert_exit_code "--no-test-suite allows all test:none" "0" "$rc"

# ── Test 10: single task with test:none ──────────────────────────────
echo "=== single task with test:none ==="

SINGLE_FILE="$TMPDIR_TEST/single-testnone.yaml"
cat > "$SINGLE_FILE" <<'EOF'
---
slug: single-feature
title: Feature with one task
status: planned
---
## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions across the entire application (test: none — trivial one-off change)
EOF

set +e
output=$("$VALIDATE_SH" "$SINGLE_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "single task rejected (min 2 tasks)" "1" "$rc"
assert_contains "mentions minimum tasks" "Only 1 task" "$output"

# ── Test 11: Multi-line plan format with indented sub-lines ───────────
echo "=== multi-line plan format ==="

MULTILINE_FILE="$TMPDIR_TEST/multi-line.yaml"
cat > "$MULTILINE_FILE" <<'EOF'
---
slug: multi-line-feature
title: Feature using multi-line plan format
status: planned
---
## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions across the entire application across the entire application stack thoroughly
  - files: src/auth.ts, src/auth.test.ts
  - test: pnpm test -- auth
  - depends: none
2. [ ] Add the user profile page with avatar upload and comprehensive form validation for all required input fields across the entire user-facing interface across every single user-facing component
  - files: src/profile.ts
  - test: none (CSS-only change, no testable behavior)
  - depends: task-1
3. [ ] Write integration tests for the complete login flow covering success failure timeout and all edge cases thoroughly across every relevant component including retry and fallback scenarios
  - files: tests/integration.ts
  - test: pnpm test -- integration
EOF

set +e
output=$("$VALIDATE_SH" "$MULTILINE_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "multi-line format accepted" "0" "$rc"

# ── Test 12: Empty test: annotation rejected ──────────────────────────
echo "=== empty test annotation rejected ==="

EMPTY_TEST_FILE="$TMPDIR_TEST/empty-test.yaml"
cat > "$EMPTY_TEST_FILE" <<'EOF'
---
slug: empty-test-feature
title: Feature with empty test annotation
status: planned
---
## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions across the entire application
  - files: src/auth.ts
  - test:
2. [ ] Write integration tests for the complete login flow covering success failure timeout and all edge cases thoroughly across every relevant component
  - test: pnpm test
EOF

set +e
output=$("$VALIDATE_SH" "$EMPTY_TEST_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "empty test annotation rejected" "1" "$rc"
assert_contains "mentions empty test" "empty test" "$output"

# ── Test 13: Missing file rejected ──────────────────────────────────
echo "=== missing file rejected ==="

set +e
output=$("$VALIDATE_SH" "$TMPDIR_TEST/nonexistent-file.yaml" 2>&1)
rc=$?
set -e
assert_exit_code "missing file rejected" "1" "$rc"
assert_contains "mentions file not found" "file not found" "$output"

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
  exit 1
fi
